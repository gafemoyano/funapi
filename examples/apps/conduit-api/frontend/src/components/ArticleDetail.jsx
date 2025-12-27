import { useState, useEffect } from 'react';
import { articles, comments } from '../services/api';
import { useAuth } from '../hooks/useAuth';
import { marked } from 'marked';

export default function ArticleDetail({ slug, onNavigate }) {
  const [article, setArticle] = useState(null);
  const [commentList, setCommentList] = useState([]);
  const [newComment, setNewComment] = useState('');
  const [loading, setLoading] = useState(true);
  const { user } = useAuth();

  useEffect(() => {
    loadArticle();
    loadComments();
  }, [slug]);

  const loadArticle = async () => {
    try {
      const data = await articles.get(slug);
      setArticle(data);
    } catch (error) {
      console.error('Failed to load article:', error);
    } finally {
      setLoading(false);
    }
  };

  const loadComments = async () => {
    try {
      const data = await comments.list(slug);
      setCommentList(data);
    } catch (error) {
      console.error('Failed to load comments:', error);
    }
  };

  const handleDelete = async () => {
    if (!confirm('Delete this article?')) return;
    try {
      await articles.delete(slug);
      onNavigate('home');
    } catch (error) {
      console.error('Failed to delete article:', error);
    }
  };

  const handleFavorite = async () => {
    if (!user) {
      onNavigate('login');
      return;
    }
    try {
      const updated = article.favorited
        ? await articles.unfavorite(slug)
        : await articles.favorite(slug);
      setArticle(updated);
    } catch (error) {
      console.error('Failed to toggle favorite:', error);
    }
  };

  const handleCommentSubmit = async (e) => {
    e.preventDefault();
    if (!newComment.trim()) return;

    try {
      await comments.create(slug, { body: newComment });
      setNewComment('');
      loadComments();
    } catch (error) {
      console.error('Failed to create comment:', error);
    }
  };

  const handleCommentDelete = async (id) => {
    try {
      await comments.delete(slug, id);
      loadComments();
    } catch (error) {
      console.error('Failed to delete comment:', error);
    }
  };

  if (loading) {
    return <div className="container mx-auto px-4 py-8 text-center">Loading...</div>;
  }

  if (!article) {
    return <div className="container mx-auto px-4 py-8 text-center">Article not found</div>;
  }

  const isAuthor = user && user.username === article.author.username;

  return (
    <div>
      {/* Article Header */}
      <div className="bg-gray-800 text-white py-8 mb-8">
        <div className="container mx-auto px-4">
          <h1 className="text-4xl font-bold mb-4">{article.title}</h1>
          <div className="flex items-center justify-between">
            <div className="flex items-center">
              <button
                onClick={() => onNavigate('profile', article.author.username)}
                className="flex items-center hover:underline"
              >
                {article.author.image && (
                  <img
                    src={article.author.image}
                    alt={article.author.username}
                    className="w-10 h-10 rounded-full mr-3"
                  />
                )}
                <div>
                  <div className="font-medium">{article.author.username}</div>
                  <div className="text-sm text-gray-400">
                    {new Date(article.createdAt).toLocaleDateString()}
                  </div>
                </div>
              </button>
            </div>

            <div className="flex gap-2">
              {isAuthor ? (
                <>
                  <button
                    onClick={() => onNavigate('editor', article)}
                    className="px-4 py-2 border border-gray-500 rounded hover:bg-gray-700"
                  >
                    Edit Article
                  </button>
                  <button
                    onClick={handleDelete}
                    className="px-4 py-2 border border-red-500 text-red-500 rounded hover:bg-red-500 hover:text-white"
                  >
                    Delete Article
                  </button>
                </>
              ) : (
                <button
                  onClick={handleFavorite}
                  className={`px-4 py-2 border rounded ${
                    article.favorited
                      ? 'bg-conduit-green border-conduit-green'
                      : 'border-conduit-green text-conduit-green hover:bg-conduit-green hover:text-white'
                  }`}
                >
                  ♥ Favorite ({article.favoritesCount})
                </button>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* Article Body */}
      <div className="container mx-auto px-4 max-w-3xl mb-12">
        <div
          className="prose max-w-none mb-8"
          dangerouslySetInnerHTML={{ __html: marked(article.body) }}
        />

        <div className="flex gap-2 mb-8">
          {article.tagList.map((tag) => (
            <span
              key={tag}
              className="px-3 py-1 border border-gray-300 rounded-full text-sm text-gray-600"
            >
              {tag}
            </span>
          ))}
        </div>

        <hr className="my-8" />

        {/* Comments Section */}
        <div className="max-w-2xl mx-auto">
          <h3 className="text-2xl font-semibold mb-4">Comments</h3>

          {user ? (
            <form onSubmit={handleCommentSubmit} className="mb-6">
              <textarea
                value={newComment}
                onChange={(e) => setNewComment(e.target.value)}
                placeholder="Write a comment..."
                className="w-full px-4 py-3 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-conduit-green"
                rows="3"
              />
              <button
                type="submit"
                className="mt-2 px-4 py-2 bg-conduit-green text-white rounded hover:bg-green-600"
              >
                Post Comment
              </button>
            </form>
          ) : (
            <p className="mb-6 text-gray-600">
              <button onClick={() => onNavigate('login')} className="text-conduit-green hover:underline">
                Sign in
              </button> or{' '}
              <button onClick={() => onNavigate('register')} className="text-conduit-green hover:underline">
                sign up
              </button> to add comments.
            </p>
          )}

          <div className="space-y-4">
            {commentList.map((comment) => (
              <div key={comment.id} className="border border-gray-200 rounded-md">
                <div className="p-4">
                  <p className="text-gray-800">{comment.body}</p>
                </div>
                <div className="bg-gray-100 px-4 py-2 flex justify-between items-center">
                  <button
                    onClick={() => onNavigate('profile', comment.author.username)}
                    className="flex items-center hover:underline text-sm"
                  >
                    {comment.author.image && (
                      <img
                        src={comment.author.image}
                        alt={comment.author.username}
                        className="w-6 h-6 rounded-full mr-2"
                      />
                    )}
                    <span className="text-conduit-green">{comment.author.username}</span>
                    <span className="ml-2 text-gray-500">
                      {new Date(comment.createdAt).toLocaleDateString()}
                    </span>
                  </button>
                  {user && user.username === comment.author.username && (
                    <button
                      onClick={() => handleCommentDelete(comment.id)}
                      className="text-red-500 hover:text-red-700 text-sm"
                    >
                      Delete
                    </button>
                  )}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
