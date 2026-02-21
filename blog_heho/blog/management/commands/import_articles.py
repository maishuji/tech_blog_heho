'''
Django management command to import blog articles from GitHub repository
'''
import json
import os
import re
from urllib import request
from urllib.error import URLError
from django.core.management.base import BaseCommand
from blog.models import BlogPost, Tag


class Command(BaseCommand):
    '''
    Import articles from GitHub repository
    '''
    help = 'Import articles from GitHub repository'

    def add_arguments(self, parser):
        parser.add_argument(
            '--repo',
            default='maishuji/tech-blog-articles',
            help='GitHub repository (owner/repo)'
        )
        parser.add_argument(
            '--branch',
            default='master',
            help='Branch name'
        )
        parser.add_argument(
            '--update',
            action='store_true',
            help='Update existing articles'
        )
        parser.add_argument(
            '--token',
            default=None,
            help='GitHub Personal Access Token for private repos'
        )

    def handle(self, *args, **options):
        repo = options['repo']
        branch = options['branch']
        update_existing = options['update']
        token = options.get('token') or self.get_token_from_env()

        # GitHub API to get repo contents
        api_url = f"https://api.github.com/repos/{repo}/contents?ref={branch}"

        self.stdout.write(self.style.NOTICE(f'Fetching articles from {repo}...'))

        try:
            files = self.fetch_repository_files(api_url, token)
            stats = self.process_articles(files, update_existing)
            self.print_import_summary(stats)

        except URLError as e:
            self.stdout.write(self.style.ERROR(f'Network error: {str(e)}'))
        except (ValueError, KeyError) as e:
            self.stdout.write(self.style.ERROR(f'Error: {str(e)}'))

    def fetch_repository_files(self, api_url, token):
        '''
        Fetch files from GitHub repository API
        '''
        req = request.Request(api_url)
        if token:
            req.add_header('Authorization', f'token {token}')
            self.stdout.write(self.style.NOTICE('Using GitHub authentication'))

        with request.urlopen(req) as response:
            if response.status != 200:
                self.stdout.write(
                    self.style.ERROR(f'Failed to fetch repository: HTTP {response.status}')
                )
                return []
            return json.loads(response.read().decode())

    def process_articles(self, files, update_existing):
        '''
        Process all markdown files and return import statistics
        '''
        stats = {'created': 0, 'updated': 0, 'skipped': 0}

        for file_info in files:
            if file_info['name'].endswith('.md'):
                result = self.import_article(file_info, update_existing)
                if result in stats:
                    stats[result] += 1

        return stats

    def print_import_summary(self, stats):
        '''
        Print import summary statistics
        '''
        self.stdout.write(self.style.SUCCESS(
            f'\n✅ Import complete!\n'
            f'   Created: {stats["created"]}\n'
            f'   Updated: {stats["updated"]}\n'
            f'   Skipped: {stats["skipped"]}'
        ))

    def get_token_from_env(self):
        '''
        Get GitHub token from environment variable
        '''
        return os.environ.get('GITHUB_TOKEN')

    def import_article(self, file_info, update_existing):
        '''
        Import a single article from GitHub
        '''
        try:
            # Download markdown content
            download_url = file_info['download_url']

            # Create request with authentication if needed
            token = self.get_token_from_env()
            req = request.Request(download_url)
            if token:
                req.add_header('Authorization', f'token {token}')

            with request.urlopen(req) as response:
                content = response.read().decode('utf-8')

            # Parse title from markdown (first # heading)
            title = self.extract_title(content, file_info['name'])

            # Remove the title from content if found
            content = self.remove_title_from_content(content)

            # Check if post already exists
            existing_post = BlogPost.objects.filter(title=title).first()

            if existing_post:
                if update_existing:
                    existing_post.content = content
                    existing_post.save()

                    # Clear old tags and add new ones from content
                    existing_post.tags.clear()
                    tags = self.extract_tags(content)
                    if tags:
                        for tag_name in tags:
                            tag, _ = Tag.objects.get_or_create(name=tag_name)
                            existing_post.tags.add(tag)
                        self.stdout.write(
                            self.style.WARNING(f'Updated: {title} (tags: {", ".join(tags)})')
                        )
                    else:
                        self.stdout.write(
                            self.style.WARNING(f'Updated: {title} (no tags found)')
                        )
                    return 'updated'
                self.stdout.write(
                    self.style.NOTICE(f'Skipped (exists): {title}')
                )
                return 'skipped'

            # Create new post
            post = BlogPost.objects.create(
                title=title,
                content=content
            )

            # Extract and create tags from article content
            tags = self.extract_tags(content)
            if tags:
                for tag_name in tags:
                    tag, _ = Tag.objects.get_or_create(name=tag_name)
                    post.tags.add(tag)
                self.stdout.write(
                    self.style.SUCCESS(f'Created: {title} (tags: {", ".join(tags)})')
                )
            else:
                self.stdout.write(
                    self.style.SUCCESS(f'Created: {title} (no tags found)')
                )
            return 'created'

        except (URLError, KeyError, ValueError) as e:
            self.stdout.write(
                self.style.ERROR(f'Error importing {file_info["name"]}: {str(e)}')
            )
            return 'error'

    def extract_title(self, content, filename):
        '''
        Extract title from markdown content (first # heading)
        Falls back to filename if no heading found
        '''
        # Look for first # heading
        match = re.search(r'^#\s+(.+)$', content, re.MULTILINE)
        if match:
            return match.group(1).strip()

        # Fallback: use filename without extension
        return filename.replace('.md', '').replace('-', ' ').replace('_', ' ').title()

    def remove_title_from_content(self, content):
        '''
        Remove the first # heading from content to avoid duplication
        '''
        # Remove first # heading line
        return re.sub(r'^#\s+.+$\n?', '', content, count=1, flags=re.MULTILINE)

    def extract_tags(self, content):
        '''
        Extract tags from article content using HTML comment format
        Example: <!--tags: cpp, design, best practices -->
        Converts to lowercase and replaces spaces with hyphens in multi-word tags
        '''
        # Look for HTML comment with tags or keywords
        pattern = r'<!--\s*(?:tags|keywords)\s*:\s*(.+?)\s*-->'
        match = re.search(pattern, content, re.IGNORECASE | re.DOTALL)

        if not match:
            return []

        tags_line = match.group(1).strip()

        # Split by comma and clean up
        raw_tags = [tag.strip() for tag in tags_line.split(',')]

        # Process each tag: lowercase and replace spaces with hyphens
        processed_tags = []
        for tag in raw_tags:
            if tag:
                # Convert to lowercase and replace spaces with hyphens
                processed_tag = tag.lower().replace(' ', '-')
                processed_tags.append(processed_tag)
        return processed_tags
