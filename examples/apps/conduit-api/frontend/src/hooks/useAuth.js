import { useState, useEffect, createContext, useContext } from 'react';
import { auth, getToken } from '../services/api';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    // Check if user is logged in on mount
    const token = getToken();
    if (token) {
      auth.getCurrentUser()
        .then(setUser)
        .catch(() => auth.logout())
        .finally(() => setLoading(false));
    } else {
      setLoading(false);
    }
  }, []);

  const login = async (email, password) => {
    const user = await auth.login({ email, password });
    setUser(user);
    return user;
  };

  const register = async (username, email, password) => {
    const user = await auth.register({ username, email, password });
    setUser(user);
    return user;
  };

  const logout = () => {
    auth.logout();
    setUser(null);
  };

  const updateUser = async (updates) => {
    const updated = await auth.updateUser(updates);
    setUser(updated);
    return updated;
  };

  return (
    <AuthContext.Provider value={{ user, loading, login, register, logout, updateUser }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within AuthProvider');
  }
  return context;
}
