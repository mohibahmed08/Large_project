import React, { useState, useEffect } from 'react';
import './login.css';

const Login = ({ setIsAuthenticated }) => {
  const [isLogin, setIsLogin] = useState(true);
  const [showPassword, setShowPassword] = useState(false);

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');

  const [passwordsMatch, setPasswordsMatch] = useState(true);

  useEffect(() => {
    if (!isLogin && confirmPassword.length > 0) {
      setPasswordsMatch(password === confirmPassword);
    } else {
      setPasswordsMatch(true);
    }
  }, [password, confirmPassword, isLogin]);

  const handleSubmit = (e) => {
    e.preventDefault();
    if (!isLogin && !passwordsMatch) return;

    const payload = isLogin 
      ? { email, password } 
      : { email, password, confirmPassword };

    console.log(`${isLogin ? 'Login' : 'Register'} Attempt:`, payload);

    setIsAuthenticated(true);
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-900 p-4">
      <div className="w-full max-w-md rounded-xl bg-gray-800 p-8 shadow-2xl text-white border border-gray-700">
        
        {/* Tab Switcher */}
        <div className="mb-8 flex border-b border-gray-700">
          <button 
            type="button"
            onClick={() => setIsLogin(true)}
            className={`flex-1 pb-4 text-sm font-semibold transition-all ${isLogin ? 'border-b-2 border-blue-500 text-blue-500' : 'text-gray-400 hover:text-gray-200'}`}
          >
            LOGIN
          </button>
          <button 
            type="button"
            onClick={() => setIsLogin(false)}
            className={`flex-1 pb-4 text-sm font-semibold transition-all ${!isLogin ? 'border-b-2 border-blue-500 text-blue-500' : 'text-gray-400 hover:text-gray-200'}`}
          >
            REGISTER
          </button>
        </div>

        <h2 className="mb-6 text-2xl font-bold text-center">
          {isLogin ? 'Welcome Back' : 'Create Account'}
        </h2>
        
        <form onSubmit={handleSubmit} className="space-y-5">
          <div>
            <label className="block text-xs font-uppercase tracking-wider text-gray-400 mb-1 font-bold">EMAIL ADDRESS</label>
            <input 
              type="email" 
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full rounded-lg border border-gray-700 bg-gray-900 p-3 focus:border-blue-500 focus:ring-1 focus:ring-blue-500 outline-none transition-all" 
              placeholder="johndoe@example.com"
              required 
            />
          </div>

          <div className="relative">
            <label className="block text-xs font-uppercase tracking-wider text-gray-400 mb-1 font-bold">PASSWORD</label>
            <input 
              type={showPassword ? "text" : "password"} 
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className={`w-full rounded-lg border bg-gray-900 p-3 focus:ring-1 outline-none transition-all ${!passwordsMatch && !isLogin ? 'border-red-500 focus:ring-red-500' : 'border-gray-700 focus:border-blue-500 focus:ring-blue-500'}`} 
              placeholder="••••••••"
              required 
            />
            <button 
              type="button"
              onClick={() => setShowPassword(!showPassword)}
              className="absolute right-3 top-9 text-[10px] font-bold text-gray-500 hover:text-blue-400 transition-colors"
            >
              {showPassword ? 'HIDE' : 'SHOW'}
            </button>
          </div>

          {!isLogin && (
            <div className="animate-in fade-in slide-in-from-top-2 duration-300">
              <label className="block text-xs font-uppercase tracking-wider text-gray-400 mb-1 font-bold">CONFIRM PASSWORD</label>
              <input 
                type={showPassword ? "text" : "password"} 
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                className={`w-full rounded-lg border bg-gray-900 p-3 focus:ring-1 outline-none transition-all ${!passwordsMatch ? 'border-red-500 focus:ring-red-500' : 'border-gray-700 focus:border-blue-500 focus:ring-blue-500'}`} 
                placeholder="••••••••"
                required 
              />
              {!passwordsMatch && (
                <p className="mt-2 text-xs font-bold text-red-500 animate-pulse">
                  Passwords do not match
                </p>
              )}
            </div>
          )}

          <button 
            type="submit" 
            disabled={!passwordsMatch && !isLogin}
            className={`w-full rounded-lg py-3 font-bold shadow-lg transition-all active:scale-[0.98] ${!passwordsMatch && !isLogin ? 'bg-gray-700 text-gray-500 cursor-not-allowed' : 'bg-blue-600 hover:bg-blue-500 text-white shadow-blue-900/20'}`}
          >
            {isLogin ? 'Sign In' : 'Get Started'}
          </button>
        </form>

        <p className="mt-6 text-center text-sm text-gray-500">
          {isLogin ? "Don't have an account?" : "Already have an account?"} 
          <button 
            type="button"
            onClick={() => setIsLogin(!isLogin)}
            className="ml-1 text-blue-400 hover:underline font-medium"
          >
            {isLogin ? 'Register now' : 'Log in here'}
          </button>
        </p>
      </div>
    </div>
  );
};

export default Login;