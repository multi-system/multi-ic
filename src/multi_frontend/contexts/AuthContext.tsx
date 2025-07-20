import React, { createContext, useContext, useEffect, useState } from 'react';
import { AuthClient } from '@dfinity/auth-client';
import { Ed25519KeyIdentity } from '@dfinity/identity';
import { Principal } from '@dfinity/principal';

interface AuthContextType {
  isAuthenticated: boolean;
  principal: Principal | null;
  login: () => Promise<void>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | null>(null);

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (!context) throw new Error('useAuth must be used within AuthProvider');
  return context;
};

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [principal, setPrincipal] = useState<Principal | null>(null);
  const [authClient, setAuthClient] = useState<AuthClient | null>(null);

  useEffect(() => {
    // Auto-login with test identity in development
    if (import.meta.env.DEV && import.meta.env.VITE_TEST_PRINCIPAL) {
      // Use the test principal from .env.local
      const testPrincipal = Principal.fromText(import.meta.env.VITE_TEST_PRINCIPAL);
      setPrincipal(testPrincipal);
      setIsAuthenticated(true);
      console.log('Dev mode: Auto-logged in with test principal:', testPrincipal.toText());
    } else {
      // Production: Create auth client for real login
      AuthClient.create().then(setAuthClient);
    }
  }, []);

  const login = async () => {
    // In dev with test principal, already logged in
    if (import.meta.env.DEV && isAuthenticated) return;
    
    if (!authClient) return;
    
    // Real Internet Identity login
    await authClient.login({
      identityProvider: `http://${import.meta.env.VITE_CANISTER_ID_INTERNET_IDENTITY}.localhost:4943`,
      onSuccess: () => {
        setIsAuthenticated(true);
        setPrincipal(authClient.getIdentity().getPrincipal());
      },
    });
  };

  const logout = async () => {
    await authClient?.logout();
    setIsAuthenticated(false);
    setPrincipal(null);
  };

  return (
    <AuthContext.Provider value={{ isAuthenticated, principal, login, logout }}>
      {children}
    </AuthContext.Provider>
  );
};