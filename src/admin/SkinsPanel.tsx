import { lazy, Suspense, useCallback, useEffect, useMemo, useState } from 'react';
import { Check, Palette, Pencil, Plus, RefreshCw, Save, Trash2, X } from 'lucide-react';
import { createGame, makeMove } from '../game/core';
import { activeSkin, type Skin, type SkinCatalog, type SkinPalette } from '../skins/catalog';
import { useAppearance } from '../store/appearanceStore';
import { adminApi } from './api';
import styles from './SkinsPanel.module.css';

const GameScene = lazy(() => import('../scene/GameScene'));
type Draft = { id: string | null; name: string; palette: SkinPalette };
const fields = [
  ['board', 'body', 'Поверхность доски'],
  ['board', 'rim', 'Ободки ячеек'],
  ['board', 'dot', 'Точки ячеек'],
  ['dark', 'body', 'Тёмные фишки'],
  ['dark', 'cap', 'Верх тёмных фишек'],
  ['dark', 'mark', 'Метка тёмных фишек'],
  ['light', 'body', 'Светлые фишки'],
  ['light', 'cap', 'Верх светлых фишек'],
  ['light', 'mark', 'Метка светлых фишек'],
] as const;
function previewGame() {
  let game = createGame();
  for (const [x, y] of [
    [0, 0],
    [2, 2],
    [1, 0],
    [2, 2],
    [0, 0],
    [3, 1],
    [3, 1],
    [2, 2],
    [1, 0],
    [4, 4],
    [3, 1],
    [4, 4],
  ]) {
    const result = makeMove(game, x, y);
    if (result.valid) game = result.state;
  }
  return game;
}
function Swatch({ skin }: { skin: Skin }) {
  return (
    <svg viewBox="0 0 200 105" aria-hidden="true">
      <rect x="15" y="19" width="170" height="72" rx="15" fill="#343b3b" />
      <rect x="15" y="15" width="170" height="72" rx="15" fill={skin.palette.board.body} />
      {[0, 1, 2, 3, 4].map((column) =>
        [0, 1, 2].map((row) => (
          <circle
            key={`${column}-${row}`}
            cx={37 + column * 31}
            cy={30 + row * 21}
            r="8"
            fill="none"
            stroke={skin.palette.board.rim}
            strokeWidth="1"
          />
        )),
      )}
      {[
        [1, 0, 'light'],
        [2, 1, 'dark'],
        [3, 0, 'dark'],
        [3, 2, 'light'],
      ].map(([x, y, owner], i) => {
        const palette = skin.palette[owner as 'light' | 'dark'];
        return (
          <g key={i}>
            <circle cx={37 + Number(x) * 31} cy={30 + Number(y) * 21} r="9" fill={palette.body} />
            <circle cx={37 + Number(x) * 31} cy={28 + Number(y) * 21} r="7" fill={palette.cap} />
          </g>
        );
      })}
      <rect x="89" y="84" width="23" height="3" rx="1.5" fill={skin.palette.accent} />
    </svg>
  );
}
export default function SkinsPanel({ onUnauthorized }: { onUnauthorized: () => void }) {
  const catalog = useAppearance((state) => state.catalog);
  const [selectedId, setSelectedId] = useState(catalog.activeSkinId);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [busy, setBusy] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const game = useMemo(previewGame, []);
  const selected = catalog.skins.find((skin) => skin.id === selectedId) ?? activeSkin(catalog);
  const preview: Skin = draft
    ? { ...selected, name: draft.name, palette: draft.palette }
    : selected;
  const request = useCallback(
    async (path: string, init?: RequestInit) => {
      setBusy(true);
      setError('');
      setNotice('');
      try {
        const result = await adminApi<SkinCatalog & { savedSkinId?: string }>(path, init);
        useAppearance.getState().setCatalog(result);
        setLoaded(true);
        return result;
      } catch (reason) {
        const message = reason instanceof Error ? reason.message : 'Не удалось загрузить стили.';
        if (message === 'Войдите в админ-панель.') onUnauthorized();
        else setError(message);
        return null;
      } finally {
        setBusy(false);
      }
    },
    [onUnauthorized],
  );
  useEffect(() => {
    void request('/admin-api/skins');
  }, [request]);
  const edit = (copy: boolean) => {
    setDraft({
      id: copy ? null : selected.id,
      name: copy ? `${selected.name} — копия`.slice(0, 48) : selected.name,
      palette: structuredClone(selected.palette),
    });
    setNotice('');
    setError('');
  };
  return (
    <section className={styles.root} aria-label="Стили игры">
      <header className={styles.heading}>
        <div>
          <h1>Оформление</h1>
          <p>
            Активный стиль: <strong>{activeSkin(catalog).name}</strong>
          </p>
        </div>
        <button
          aria-label="Обновить стили"
          disabled={busy}
          onClick={() => void request('/admin-api/skins')}
        >
          <RefreshCw size={18} />
        </button>
      </header>
      {error && (
        <p role="alert" className={styles.error}>
          {error}
        </p>
      )}
      {notice && (
        <p role="status" className={styles.notice}>
          {notice}
        </p>
      )}
      <div className={styles.layout}>
        <div className={styles.catalog}>
          <div className={styles.cards}>
            {catalog.skins.map((skin) => (
              <button
                key={skin.id}
                className={styles.card}
                aria-pressed={skin.id === selected.id}
                disabled={busy || Boolean(draft)}
                onClick={() => {
                  setSelectedId(skin.id);
                  setNotice('');
                }}
              >
                <Swatch skin={skin} />
                <strong>{skin.name}</strong>
                <span>
                  {skin.id === catalog.activeSkinId ? (
                    <>
                      <Check size={13} /> Активный
                    </>
                  ) : skin.builtin ? (
                    'Готовый стиль'
                  ) : (
                    'Свой стиль'
                  )}
                </span>
              </button>
            ))}
          </div>
          <div className={styles.actions}>
            <button disabled={busy || !loaded || Boolean(draft)} onClick={() => edit(true)}>
              <Plus size={16} /> Новый стиль
            </button>
            {!selected.builtin && (
              <>
                <button disabled={busy || Boolean(draft)} onClick={() => edit(false)}>
                  <Pencil size={16} /> Изменить
                </button>
                <button
                  disabled={busy || Boolean(draft) || selected.id === catalog.activeSkinId}
                  onClick={async () => {
                    const result = await request(`/admin-api/skins/${selected.id}`, {
                      method: 'DELETE',
                      body: JSON.stringify({ expectedRevision: catalog.revision }),
                    });
                    if (result) {
                      setSelectedId(result.activeSkinId);
                      setNotice('Стиль удалён.');
                    }
                  }}
                >
                  <Trash2 size={16} /> Удалить
                </button>
              </>
            )}
          </div>
          {draft && (
            <form
              className={styles.editor}
              onSubmit={async (event) => {
                event.preventDefault();
                const result = await request(
                  draft.id ? `/admin-api/skins/${draft.id}` : '/admin-api/skins',
                  {
                    method: draft.id ? 'PATCH' : 'POST',
                    body: JSON.stringify({
                      name: draft.name.trim(),
                      palette: draft.palette,
                      expectedRevision: catalog.revision,
                    }),
                  },
                );
                if (result) {
                  setSelectedId(result.savedSkinId!);
                  setDraft(null);
                  setNotice('Стиль сохранён.');
                }
              }}
            >
              <div className={styles.editorHeading}>
                <h2>{draft.id ? 'Изменить стиль' : 'Новый стиль'}</h2>
                <button
                  type="button"
                  aria-label="Закрыть редактор стиля"
                  disabled={busy}
                  onClick={() => setDraft(null)}
                >
                  <X size={17} />
                </button>
              </div>
              <label className={styles.name}>
                Название
                <input
                  aria-label="Название стиля"
                  value={draft.name}
                  maxLength={48}
                  required
                  disabled={busy}
                  onChange={(event) => setDraft({ ...draft, name: event.target.value })}
                />
              </label>
              <div className={styles.colors}>
                {fields.map(([group, key, label]) => (
                  <label key={label}>
                    <input
                      type="color"
                      aria-label={label}
                      value={String(Reflect.get(draft.palette[group], key))}
                      disabled={busy}
                      onChange={(event) =>
                        setDraft({
                          ...draft,
                          palette: {
                            ...draft.palette,
                            [group]: { ...draft.palette[group], [key]: event.target.value },
                          },
                        })
                      }
                    />
                    <span>{label}</span>
                  </label>
                ))}
                <label>
                  <input
                    type="color"
                    aria-label="Цвет подсветки"
                    value={draft.palette.accent}
                    disabled={busy}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        palette: { ...draft.palette, accent: event.target.value },
                      })
                    }
                  />
                  <span>Подсветка и победа</span>
                </label>
              </div>
              <button className={styles.primary} disabled={busy}>
                <Save size={16} /> Сохранить стиль
              </button>
            </form>
          )}
        </div>
        <section className={styles.preview} aria-label="Предпросмотр стиля">
          <header>
            <Palette size={17} />
            <strong>{preview.name}</strong>
          </header>
          <div className={styles.scene}>
            <Suspense fallback={<p>Загрузка…</p>}>
              <GameScene
                skin={preview}
                game={game}
                interactive={false}
                onPlace={() => {}}
                xray={false}
                layers={[0, 1, 2, 3, 4]}
                cameraView="perspective"
                cameraReset={0}
                animations={false}
                hints={false}
                demo
                background="#ebeae7"
              />
            </Suspense>
          </div>
          <button
            className={styles.primary}
            disabled={!loaded || busy || Boolean(draft) || selected.id === catalog.activeSkinId}
            onClick={async () => {
              const result = await request('/admin-api/skins', {
                method: 'PATCH',
                body: JSON.stringify({
                  activeSkinId: selected.id,
                  expectedRevision: catalog.revision,
                }),
              });
              if (result) setNotice('Стиль применён.');
            }}
          >
            <Check size={17} />{' '}
            {selected.id === catalog.activeSkinId && !draft
              ? 'Используется в игре'
              : 'Применить для всех'}
          </button>
        </section>
      </div>
    </section>
  );
}
