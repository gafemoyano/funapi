import { useState, useEffect } from 'react';
import { articles, tags } from '../services/api';
import { useAuth } from '../hooks/useAuth';
import ArticlePreview from './ArticlePreview';

export default function Home({ onNavigate }) {
  const [articleList, setArticleList] = useState([]);
  const [tagList, setTagList] = useState([]);
  const [activeTab, setActiveTab] = useState('global');
  const [selectedTag, setSelectedTag] = useState(null);
  const [loading, setLoading] = useState(true);
  const { user } = useAuth();

  useEffect(() => {
    loadArticles();
    loadTags();
  }, [activeTab, selectedTag]);

  const loadArticles = async () => {
    setLoading(true);
    try {
      let data;
      if (activeTab === 'feed' && user) {
        data = await articles.feed();
      } else {
        const params = selectedTag ? { tag: selectedTag } : {};
        data = await articles.list(params);
      }
      setArticleList(data.articles || []);
    } catch (error) {
      console.error('Failed to load articles:', error);
    } finally {
      setLoading(false);
    }
  };

  const loadTags = async () => {
    try {
      const data = await tags.list();
      setTagList(data || []);
    } catch (error) {
      console.error('Failed to load tags:', error);
    }
  };

  const handleTagClick = (tag) => {
    setSelectedTag(tag);
    setActiveTab('global');
  };

  return (
    <div>
      {/* Hero Banner */}
      <div className="bg-conduit-green text-white py-8 mb-8 shadow-md">
        <div className="container mx-auto px-4 text-center">
          <h1 className="text-5xl font-bold mb-2">conduit</h1>
          <p className="text-xl">A place to share your knowledge.</p>
        </div>
      </div>

      <div className="container mx-auto px-4">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
          {/* Main Content */}
          <div className="md:col-span-3">
            {/* Tabs */}
            <div className="flex border-b border-gray-200 mb-4">
              {user && (
                <button
                  onClick={() => {
                    setActiveTab('feed');
                    setSelectedTag(null);
                  }}
                  className={`px-4 py-2 border-b-2 font-medium ${
                    activeTab === 'feed'
                      ? 'border-conduit-green text-conduit-green'
                      : 'border-transparent text-gray-500 hover:text-gray-700'
                  }`}
                >
                  Your Feed
                </button>
              )}
              <button
                onClick={() => {
                  setActiveTab('global');
                  setSelectedTag(null);
                }}
                className={`px-4 py-2 border-b-2 font-medium ${
                  activeTab === 'global' && !selectedTag
                    ? 'border-conduit-green text-conduit-green'
                    : 'border-transparent text-gray-500 hover:text-gray-700'
                }`}
              >
                Global Feed
              </button>
              {selectedTag && (
                <button
                  className="px-4 py-2 border-b-2 border-conduit-green text-conduit-green font-medium"
                >
                  # {selectedTag}
                </button>
              )}
            </div>

            {/* Articles */}
            {loading ? (
              <div className="text-center py-8 text-gray-500">Loading articles...</div>
            ) : articleList.length === 0 ? (
              <div className="text-center py-8 text-gray-500">No articles yet.</div>
            ) : (
              <div className="space-y-4">
                {articleList.map((article) => (
                  <ArticlePreview
                    key={article.slug}
                    article={article}
                    onNavigate={onNavigate}
                  />
                ))}
              </div>
            )}
          </div>

          {/* Sidebar */}
          <div className="md:col-span-1">
            <div className="bg-gray-100 rounded-md p-4">
              <h3 className="text-sm font-semibold mb-3">Popular Tags</h3>
              <div className="flex flex-wrap gap-2">
                {tagList.map((tag) => (
                  <button
                    key={tag}
                    onClick={() => handleTagClick(tag)}
                    className="px-2 py-1 bg-gray-600 text-white text-xs rounded-full hover:bg-gray-700"
                  >
                    {tag}
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
