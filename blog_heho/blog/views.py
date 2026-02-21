'''
Views module
'''
import markdown
from django.core.paginator import Paginator
from django.shortcuts import render, redirect, get_object_or_404
from django.core.mail import send_mail
from django.db.models import Count
from .models import BlogPost, Tag
from .forms import ContactForm, CommentForm

def blog_list(request):
    '''
    List the blog posts
    '''
    # Tag list with article counts
    tags = Tag.objects.annotate(article_count=Count('posts')).order_by('-article_count', 'name')
    posts = BlogPost.objects.all()
    selected_category = request.GET.get('category')
    if selected_category:
        posts = posts.filter(tags__slug=selected_category)

    # Pagination: Show 5 posts per page
    paginator = Paginator(posts, 5)
    page_number = request.GET.get('page')
    page_obj = paginator.get_page(page_number)

    # Convert each post's content from Markdown to HTML
    for post in page_obj:
        post.title = markdown.markdown(post.title, extensions=["extra", "fenced_code", "toc"])
        post.content = markdown.markdown(post.content, extensions=["extra", "fenced_code", "toc"])
    return render(request, 'blog/blog_list.html', {'page_obj': page_obj, 'categories': tags})

def blog_detail_view(request, post_id):
    '''
    Show a blog post details
    '''
    post = get_object_or_404(BlogPost, id=post_id)
    post.title = markdown.markdown(post.title, extensions=["extra", "fenced_code", "toc"])
    post.content = markdown.markdown(post.content, extensions=["extra", "fenced_code", "toc"])

    # Add comments to the post
    comments = post.comments.all()
    comment_form = CommentForm()
    #context = {
    #    'post': post,
    #    'comments': comments,
    #    'comment_form': comment_form,
    #}
    if request.method == 'POST':
        comment_form = CommentForm(request.POST)
        if comment_form.is_valid():
            comment = comment_form.save(commit=False)
            comment.post = post
            comment.save()
            return redirect('blog_detail', post_id=post.id)
    else:
        comment_form = CommentForm()

    return render(
        request,
        "blog/blog_detail.html", 
        {"post": post, "comments": comments, "comment_form": comment_form}
    )

def contact_view(request):
    '''
    Show the contact page, with a form to send an email
    '''
    if request.method == "POST":
        form = ContactForm(request.POST)
        if form.is_valid():
            # Extract the data from the form
            #name = form.cleaned_data['name']
            email = form.cleaned_data['email']
            subject = form.cleaned_data['subject']
            message = form.cleaned_data['message']
            # Send the email
            send_mail(subject, message, email, ['d19140e9a1-28460f@inbox.mailtrap.io'])
            return redirect('success')
    form = ContactForm()
    return render(request, "contact.html", {'form': form})

def home_view(request):
    '''
    Show the home page
    '''
    posts = BlogPost.objects.order_by('-id')[:5]  # Fetch the latest 5 blog posts
    # Keep raw content for previews - template will handle display
    return render(request, "home.html", {"posts": posts})

def about_view(request):
    '''
    Show the about page
    '''
    return render(request, "about.html")
