import { lazy, StrictMode, Suspense } from 'react';
import { createRoot } from 'react-dom/client';
import App from './app/App';
import './styles/global.css';
import { initializeAnalytics } from './network/analytics';
import { initializeOffline } from './network/offline';
import { initializeTelegram, loadTelegramSDK } from './telegram/bridge';
import { installGameTouchGuard } from './telegram/touchGuard';
import { initializeAppearance } from './store/appearanceStore';

const AdminApp = lazy(() => import('./admin/AdminApp'));
// Home-screen Safari can omit version tokens and use navigator.standalone.
const ios =
  /iPad|iPhone|iPod/.test(navigator.userAgent) ||
  (/Macintosh/.test(navigator.userAgent) && navigator.maxTouchPoints > 1);
const standalone = window.matchMedia('(display-mode: standalone)');
function updateStandalone() {
  document.documentElement.toggleAttribute(
    'data-ios-standalone',
    ios &&
      (standalone.matches ||
        (navigator as Navigator & { standalone?: boolean }).standalone === true),
  );
}
updateStandalone();
initializeAppearance();
standalone.addEventListener('change', updateStandalone);
if (!window.location.pathname.startsWith('/admin')) {
  document.getElementById('root')!.dataset.gameInterface = 'true';
  installGameTouchGuard();
  initializeOffline();
  initializeAnalytics();
}

async function mount() {
  await loadTelegramSDK();
  initializeTelegram();
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
}
void mount();
