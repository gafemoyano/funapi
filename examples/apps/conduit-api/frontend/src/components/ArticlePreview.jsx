import { useState } from 'react';
import { articles } from '../services/api';
import { useAuth } from '../hooks/useAuth';

export default function ArticlePreview({ article, onNavigate }) {
  const [favorited, setFavorited] = useState(article.favorited);
  const [favoritesCount, setFavoritesCount] = useState(article.favoritesCount);
  const { user } = useAuth();

  const handleFavorite = async (e) => {
    e.stopPropagation();
    if (!user) {
      onNavigate('login');
      return;
    }

    try {
      const updated = favorited
        ? await articles.unfavorite(article.slug)
        : await articles.favorite(article.slug);
      setFavorited(updated.favorited);
      setFavoritesCount(updated.favoritesCount);
    } catch (error) {
      console.error('Failed to toggle favorite:', error);
    }
  };

  return (
    <div className="bg-white border border-gray-200 rounded-md p-4 hover:shadow-md transition-shadow">
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center">
          <button
            onClick={() => onNavigate('profile', article.author.username)}
            className="flex items-center hover:underline"
          >
            {article.author.image && (
              <img
                src={article.author.image}
                alt={article.author.username}
                className="w-8 h-8 rounded-full mr-2"
              />
            )}
            <div>
              <div className="text-conduit-green font-medium text-sm">
                {article.author.username}
              </div>
              <div className="text-gray-500 text-xs">
                {new Date(article.createdAt).toLocaleDateString()}
              </div>
            </div>
          </button>
        </div>

        <button
          onClick={handleFavorite}
          className={`px-3 py-1 border rounded text-sm ${
            favorited
              ? 'bg-conduit-green text-white border-conduit-green'
              : 'border-conduit-green text-conduit-green hover:bg-conduit-green hover:text-white'
          }`}
        >
          ♥ {favoritesCount}
        </button>
      </div>

      <button
        onClick={() => onNavigate('article', article.slug)}
        className="text-left w-full"
      >
        <h2 className="text-xl font-semibold text-gray-900 mb-1 hover:text-conduit-green">
          {article.title}
        </h2>
        <p className="text-gray-600 text-sm mb-3">{article.description}</p>
        <div className="flex justify-between items-center text-sm">
          <span className="text-gray-500">Read more...</span>
          <div className="flex gap-1">
            {article.tagList.map((tag) => (
              <span
                key={tag}
                className="px-2 py-1 border border-gray-300 rounded-full text-xs text-gray-600"
              >
                {tag}
              </span>
            ))}
          </div>
        </div>
      </button>
    </div>
  );
}
