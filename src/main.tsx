import { lazy, StrictMode, Suspense } from 'react';
import { createRoot } from 'react-dom/client';
import App from './app/App';
import './styles/global.css';
import { initializeAnalytics } from './network/analytics';

const AdminApp = lazy(() => import('./admin/AdminApp'));
if (!window.location.pathname.startsWith('/admin')) initializeAnalytics();

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    {window.location.pathname.startsWith('/admin') ? (
      <Suspense fallback={null}>
        <AdminApp />
      </Suspense>
    ) : (
      <App />
    )}
  </StrictMode>,
);
