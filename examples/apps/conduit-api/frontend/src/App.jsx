import { useState } from 'react';
import { AuthProvider, useAuth } from './hooks/useAuth';
import Header from './components/Header';
import Home from './components/Home';
import Login from './components/Login';
import Register from './components/Register';
import ArticleDetail from './components/ArticleDetail';
import Editor from './components/Editor';
import Profile from './components/Profile';
import Settings from './components/Settings';

function AppContent() {
  const [currentPage, setCurrentPage] = useState('home');
  const [selectedArticle, setSelectedArticle] = useState(null);
  const [selectedProfile, setSelectedProfile] = useState(null);
  const [editArticle, setEditArticle] = useState(null);
  const { user } = useAuth();

  const navigate = (page, data = null) => {
    setCurrentPage(page);
    if (page === 'article') setSelectedArticle(data);
    if (page === 'profile') setSelectedProfile(data);
    if (page === 'editor') setEditArticle(data);
  };

  const renderPage = () => {
    switch (currentPage) {
      case 'login':
        return <Login onNavigate={navigate} />;
      case 'register':
        return <Register onNavigate={navigate} />;
      case 'article':
        return <ArticleDetail slug={selectedArticle} onNavigate={navigate} />;
      case 'editor':
        return <Editor article={editArticle} onNavigate={navigate} />;
      case 'profile':
        return <Profile username={selectedProfile} onNavigate={navigate} />;
      case 'settings':
        return <Settings onNavigate={navigate} />;
      default:
        return <Home onNavigate={navigate} />;
    }
  };

  return (
    <div className="min-h-screen bg-gray-100">
      <Header currentPage={currentPage} onNavigate={navigate} />
      <main>
        {renderPage()}
      </main>
      <footer className="bg-gray-800 text-white py-6 mt-12">
        <div className="container mx-auto px-4 text-center">
          <p className="text-sm">
            Built with <span className="text-conduit-green">FunApi</span> + React 19
          </p>
          <p className="text-xs mt-2 text-gray-400">
            A RealWorld fullstack example
          </p>
        </div>
      </footer>
    </div>
  );
}

export default function App() {
  return (
    <AuthProvider>
      <AppContent />
    </AuthProvider>
  );
}
