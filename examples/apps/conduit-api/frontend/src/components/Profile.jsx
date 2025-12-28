import { useState, useEffect } from 'react';
import { profiles, articles } from '../services/api';
import { useAuth } from '../hooks/useAuth';
import ArticlePreview from './ArticlePreview';

export default function Profile({ username, onNavigate }) {
  const [profile, setProfile] = useState(null);
  const [articleList, setArticleList] = useState([]);
  const [loading, setLoading] = useState(true);
  const { user } = useAuth();

  useEffect(() => {
    loadProfile();
    loadArticles();
  }, [username]);

  const loadProfile = async () => {
    try {
      const data = await profiles.get(username);
      setProfile(data);
    } catch (error) {
      console.error('Failed to load profile:', error);
    } finally {
      setLoading(false);
    }
  };

  const loadArticles = async () => {
    try {
      const data = await articles.list({ author: username });
      setArticleList(data.articles || []);
    } catch (error) {
      console.error('Failed to load articles:', error);
    }
  };

  const handleFollow = async () => {
    if (!user) {
      onNavigate('login');
      return;
    }

    try {
      const updated = profile.following
        ? await profiles.unfollow(username)
        : await profiles.follow(username);
      setProfile(updated);
    } catch (error) {
      console.error('Failed to toggle follow:', error);
    }
  };

  if (loading) {
    return <div className="container mx-auto px-4 py-8 text-center">Loading...</div>;
  }

  if (!profile) {
    return <div className="container mx-auto px-4 py-8 text-center">Profile not found</div>;
  }

  const isOwnProfile = user && user.username === username;

  return (
    <div>
      {/* Profile Header */}
      <div className="bg-gray-100 border-b border-gray-200 py-8 mb-8">
        <div className="container mx-auto px-4 text-center">
          {profile.image && (
            <img
              src={profile.image}
              alt={username}
              className="w-24 h-24 rounded-full mx-auto mb-4"
            />
          )}
          <h1 className="text-3xl font-bold mb-2">{username}</h1>
          {profile.bio && <p className="text-gray-600">{profile.bio}</p>}

          <div className="mt-4">
            {isOwnProfile ? (
              <button
                onClick={() => onNavigate('settings')}
                className="px-4 py-2 border border-gray-400 rounded hover:bg-gray-200"
              >
                Edit Profile Settings
              </button>
            ) : (
              <button
                onClick={handleFollow}
                className={`px-4 py-2 border rounded ${
                  profile.following
                    ? 'border-gray-400 bg-gray-700 text-white'
                    : 'border-gray-400 hover:bg-gray-200'
                }`}
              >
                {profile.following ? '− Unfollow' : '+ Follow'} {username}
              </button>
            )}
          </div>
        </div>
      </div>

      {/* Articles */}
      <div className="container mx-auto px-4 max-w-4xl">
        <div className="mb-6">
          <h2 className="text-2xl font-semibold border-b-2 border-conduit-green inline-block pb-2">
            My Articles
          </h2>
        </div>

        {articleList.length === 0 ? (
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
    </div>
  );
}
