export interface TelegramLoginSDK {
  close?(): void;
  auth(
    options: { client_id: number; scope: string[]; nonce: string; lang: string },
    callback: (data: { id_token?: string; error?: string } | null) => void,
  ): Promise<void> | void;
}
export function telegramLoginSDK(): TelegramLoginSDK | undefined {
  return (window.Telegram as unknown as { Login?: TelegramLoginSDK } | undefined)?.Login;
}
let pending: Promise<TelegramLoginSDK> | null = null;
export function loadTelegramLogin(): Promise<TelegramLoginSDK> {
  const ready = telegramLoginSDK();
  if (ready) return Promise.resolve(ready);
  if (pending) return pending;
  pending = new Promise<TelegramLoginSDK>((resolve, reject) => {
    const script = document.createElement('script');
    script.src = 'https://telegram.org/js/telegram-login.js';
    const timer = window.setTimeout(() => {
      script.remove();
      reject(new Error('Telegram не отвечает. Попробуйте снова.'));
    }, 10000);
    script.onload = () => {
      window.clearTimeout(timer);
      const sdk = telegramLoginSDK();
      if (sdk) resolve(sdk);
      else reject(new Error('Не удалось загрузить вход Telegram.'));
    };
    script.onerror = () => {
      window.clearTimeout(timer);
      script.remove();
      reject(new Error('Не удалось подключиться к Telegram.'));
    };
    document.head.append(script);
  }).catch((error) => {
    pending = null;
    throw error;
  });
  return pending;
}
