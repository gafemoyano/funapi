import { useAuth } from '../hooks/useAuth';

export default function Header({ currentPage, onNavigate }) {
  const { user, logout } = useAuth();

  return (
    <nav className="bg-white shadow-sm border-b border-gray-200">
      <div className="container mx-auto px-4">
        <div className="flex justify-between items-center h-16">
          <button
            onClick={() => onNavigate('home')}
            className="text-2xl font-bold text-conduit-green hover:text-green-600"
          >
            conduit
          </button>

          <div className="flex items-center space-x-4">
            <button
              onClick={() => onNavigate('home')}
              className={`px-3 py-2 rounded-md text-sm font-medium ${
                currentPage === 'home'
                  ? 'text-conduit-green'
                  : 'text-gray-700 hover:text-conduit-green'
              }`}
            >
              Home
            </button>

            {user ? (
              <>
                <button
                  onClick={() => onNavigate('editor')}
                  className={`px-3 py-2 rounded-md text-sm font-medium ${
                    currentPage === 'editor'
                      ? 'text-conduit-green'
                      : 'text-gray-700 hover:text-conduit-green'
                  }`}
                >
                  <span className="mr-1">+</span> New Article
                </button>
                <button
                  onClick={() => onNavigate('settings')}
                  className={`px-3 py-2 rounded-md text-sm font-medium ${
                    currentPage === 'settings'
                      ? 'text-conduit-green'
                      : 'text-gray-700 hover:text-conduit-green'
                  }`}
                >
                  Settings
                </button>
                <button
                  onClick={() => onNavigate('profile', user.username)}
                  className={`px-3 py-2 rounded-md text-sm font-medium ${
                    currentPage === 'profile'
                      ? 'text-conduit-green'
                      : 'text-gray-700 hover:text-conduit-green'
                  }`}
                >
                  {user.username}
                </button>
              </>
            ) : (
              <>
                <button
                  onClick={() => onNavigate('login')}
                  className={`px-3 py-2 rounded-md text-sm font-medium ${
                    currentPage === 'login'
                      ? 'text-conduit-green'
                      : 'text-gray-700 hover:text-conduit-green'
                  }`}
                >
                  Sign in
                </button>
                <button
                  onClick={() => onNavigate('register')}
                  className={`px-3 py-2 rounded-md text-sm font-medium ${
                    currentPage === 'register'
                      ? 'text-conduit-green'
                      : 'text-gray-700 hover:text-conduit-green'
                  }`}
                >
                  Sign up
                </button>
              </>
            )}
          </div>
        </div>
      </div>
    </nav>
  );
}
