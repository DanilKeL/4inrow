import { useRef, useState } from 'react';
import { Copy, Globe2, LogOut } from 'lucide-react';
import { useGame } from '../store/gameStore';
import styles from './UI.module.css';
import { copyText } from './clipboard';

export function OnlineLobby({ onLeave }: { onLeave: () => void }) {
  const { online, onlineStatus, onlineError, onlineKind } = useGame();
  const [copyStatus, setCopyStatus] = useState('');
  const codeElement = useRef<HTMLElement>(null);
  const code = online?.snapshot.code;
  const opponent = online?.snapshot.players[online.player === 1 ? 1 : 0];
  const ranking = online?.snapshot.ranking;
  const index = (online?.player ?? 1) - 1;
  const delta = ranking?.changes?.[index];
  const status =
    onlineStatus === 'error'
      ? onlineError || 'Соединение закрыто'
      : onlineStatus !== 'connected'
        ? 'Восстанавливаем соединение…'
        : !opponent
          ? onlineKind === 'quick'
            ? 'Ждём соперника…'
            : 'Передайте код другу — ждём второго игрока'
          : !opponent.connected
            ? 'Соперник отключился. Ждём возвращения…'
            : `Вы играете ${online?.player === 1 ? 'графитом · ●' : 'светлыми · ○'}`;
  async function copyCode() {
    if (!code) return;
    if (await copyText(code)) {
      setCopyStatus('Код скопирован');
    } else {
      if (codeElement.current) {
        const range = document.createRange();
        range.selectNodeContents(codeElement.current);
        window.getSelection()?.removeAllRanges();
        window.getSelection()?.addRange(range);
      }
      setCopyStatus('Код выделен — нажмите «Копировать»');
    }
  }
  return (
    <div className={styles.onlineBanner}>
      <div className={styles.lobbyHeading}>
        <Globe2 size={17} />
        <span>{onlineKind === 'quick' ? 'РЕЙТИНГОВАЯ ИГРА' : 'ЛОББИ'}</span>
        {code && onlineKind !== 'quick' && (
          <strong ref={codeElement} style={{ userSelect: 'text' }} data-testid="lobby-code">
            {code}
          </strong>
        )}
        {code && onlineKind !== 'quick' && (
          <button
            className={styles.iconButton}
            aria-label="Скопировать код лобби"
            onClick={() => void copyCode()}
          >
            <Copy size={16} />
          </button>
        )}
        <button
          className={styles.iconButton}
          aria-label="Покинуть лобби"
          title="Покинуть лобби"
          onClick={onLeave}
        >
          <LogOut size={17} />
        </button>
      </div>
      <p aria-live="polite" role={onlineStatus === 'error' ? 'alert' : 'status'}>
        {ranking?.rated ? (
          <span data-testid="ranked-status">
            Рейтинг: {ranking.points[index] + (delta ?? 0)}
            {delta !== undefined
              ? ` (${delta >= 0 ? '+' : ''}${delta})`
              : online?.snapshot.pause?.endsAt
                ? ' · Пауза'
                : ''}
            {online?.snapshot.endReason
              ? ` · ${online.snapshot.endReason}`
              : !opponent?.connected
                ? ' · Ждём подключения'
                : ''}
          </span>
        ) : ranking ? (
          <span title={ranking.reason}>{ranking.reason}</span>
        ) : (
          status
        )}
      </p>
      {copyStatus && <small role="status">{copyStatus}</small>}
    </div>
  );
}
