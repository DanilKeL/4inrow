import { skinImageUrl } from '../skins/imageAssets';
import { lazy, Suspense, useCallback, useEffect, useMemo, useState } from 'react';
import { Check, Palette, Pencil, Plus, RefreshCw, Save, Trash2, X } from 'lucide-react';
import { createGame, makeMove } from '../game/core';
import { activeSkin, type Skin, type SkinCatalog, type SkinPalette } from '../skins/catalog';
import {
  blankDesign,
  nocturneDesign,
  pickmiDesign,
  animeDesign,
  type SkinDesign,
  type SurfaceDesign,
} from '../skins/design';
import { useAppearance } from '../store/appearanceStore';
import { adminApi } from './api';
import SkinDesignEditor from './SkinDesignEditor';
import styles from './SkinsPanel.module.css';

const GameScene = lazy(() => import('../scene/GameScene'));
type Draft = {
  id: string | null;
  name: string;
  palette: SkinPalette;
  artwork?: Skin['artwork'];
  design?: SkinDesign;
};
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
const fieldGroups = [
  ['board', 'Доска и окружение'],
  ['dark', 'Тёмные фишки'],
  ['light', 'Светлые фишки'],
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
function SwatchDecoration({ surface }: { surface: SurfaceDesign }) {
  const motifSymbols = {
    moon: '☽',
    sun: '☀',
    star: '✧',
    lotus: '❧',
    laurel: '❦',
    diamond: '◇',
    rings: '◎',
    heart: '♥',
    bow: '⋈',
    blossom: '✿',
    sakura: '✿',
    kitsune: '◇',
    crest: '☽',
  };
  return (
    <g>
      <g fill="none" stroke={surface.ink} strokeWidth="0.7" opacity={surface.patternOpacity}>
        {surface.border && <rect x="20" y="20" width="160" height="62" rx="11" />}
        {surface.pattern === 'celestial' && (
          <>
            <circle cx="100" cy="51" r="24" />
            <ellipse cx="100" cy="51" rx="45" ry="20" transform="rotate(-25 100 51)" />
            <path d="M26 28L34 35L42 27M157 70L165 76L174 68" />
          </>
        )}
        {surface.pattern === 'botanical' && (
          <>
            <path d="M24 73Q63 12 100 51T176 30" />
            <path d="M35 52Q23 39 36 39Q46 38 42 52M153 53Q155 37 167 37Q178 45 163 52" />
          </>
        )}
        {surface.pattern === 'artdeco' && (
          <>
            <path d="M25 78L100 23L175 78M35 78L100 34L165 78M48 78L100 45L152 78" />
            <path d="M25 28L100 80L175 28" />
          </>
        )}
        {surface.pattern === 'guilloche' &&
          [0, 25, 50, 75, 100, 125, 150].map((angle) => (
            <ellipse
              key={angle}
              cx="100"
              cy="51"
              rx="60"
              ry="19"
              transform={`rotate(${angle} 100 51)`}
            />
          ))}
        {surface.pattern === 'sakura-waves' && (
          <>
            <path d="M17 75Q42 15 58 37T93 21M164 17Q150 72 120 60T79 83" />
            <path d="M19 56Q54 35 96 51T181 57M18 64Q60 43 98 59T183 65" />
            <g fill="#ed99b0" stroke="none">
              {[34, 53, 154, 126].map((x, i) => (
                <circle key={x} cx={x} cy={28 + i * 13} r="3" />
              ))}
            </g>
          </>
        )}
        {surface.pattern === 'gingham' && (
          <g fill={surface.ink} stroke="none" opacity="0.6">
            {Array.from({ length: 9 }, (_, i) => (
              <rect key={`v-${i}`} x={15 + i * 20} y="15" width="10" height="72" />
            ))}
            {Array.from({ length: 4 }, (_, i) => (
              <rect key={`h-${i}`} x="15" y={15 + i * 20} width="170" height="10" />
            ))}
          </g>
        )}
        {surface.pattern === 'marble' && (
          <>
            <path d="M15 36Q55 60 81 27T157 35L185 25M15 71Q56 43 94 65T185 40M23 78Q58 50 84 76T174 69" />
            <path d="M40 16L64 41L53 54M129 19L141 41L125 61L160 86" />
          </>
        )}
      </g>
      {surface.layers.flatMap((layer) => {
        const locations =
          layer.placement === 'corners'
            ? [
                [0.15, 0.2],
                [0.85, 0.2],
                [0.15, 0.8],
                [0.85, 0.8],
              ]
            : layer.placement === 'grid'
              ? [0.2, 0.5, 0.8].flatMap((x) => [0.2, 0.5, 0.8].map((y) => [x, y]))
              : [[layer.x, layer.y]];
        return locations.map(([x, y], index) => (
          <g
            key={`${layer.id}-${index}`}
            opacity={layer.opacity}
            transform={`translate(${15 + x * 170} ${15 + y * 72}) rotate(${layer.rotation})`}
          >
            {layer.kind === 'image' ? (
              <image
                href={skinImageUrl(layer.imageId)}
                x={-layer.size * 36}
                y={-layer.size * 36}
                width={layer.size * 72}
                height={layer.size * 72}
                preserveAspectRatio="xMidYMid meet"
              />
            ) : (
              <text
                textAnchor="middle"
                dominantBaseline="middle"
                fill={layer.color}
                fontSize={layer.size * 60}
              >
                {motifSymbols[layer.motif]}
              </text>
            )}
          </g>
        ));
      })}
    </g>
  );
}
function Swatch({ skin }: { skin: Skin }) {
  return (
    <svg viewBox="0 0 200 105" aria-hidden="true">
      <rect width="200" height="105" rx="10" fill={skin.palette.room} />
      <rect x="15" y="19" width="170" height="72" rx="15" fill="#343b3b" />
      <rect x="15" y="15" width="170" height="72" rx="15" fill={skin.palette.board.body} />
      {skin.artwork === 'nocturne' && (
        <g fill="none" stroke={skin.palette.accent} strokeWidth="0.7">
          <rect x="20" y="20" width="160" height="62" rx="11" />
          <circle cx="100" cy="51" r="24" />
          <ellipse cx="100" cy="51" rx="45" ry="20" transform="rotate(-25 100 51)" />
          <path d="M25 73Q49 31 87 56T172 30M26 28L34 35L42 27M157 70L165 76L174 68" />
        </g>
      )}
      {skin.design && (
        <svg x="15" y="15" width="170" height="72" viewBox="15 15 170 72" overflow="hidden">
          <SwatchDecoration surface={skin.design.surfaces.board} />
        </svg>
      )}
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
  const [uploading, setUploading] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const game = useMemo(previewGame, []);
  const selected = catalog.skins.find((skin) => skin.id === selectedId) ?? activeSkin(catalog);
  const locked = busy || uploading;
  const preview: Skin = draft
    ? {
        ...selected,
        name: draft.name,
        palette: draft.palette,
        artwork: draft.artwork,
        design: draft.design,
      }
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
      artwork: selected.artwork,
      design: selected.design ? structuredClone(selected.design) : undefined,
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
          disabled={locked}
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
                disabled={locked || Boolean(draft)}
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
                    skin.artwork || skin.design ? (
                      'Авторский рисунок'
                    ) : (
                      'Готовый стиль'
                    )
                  ) : (
                    'Свой стиль'
                  )}
                </span>
              </button>
            ))}
          </div>
          <div className={styles.actions}>
            <button disabled={locked || !loaded || Boolean(draft)} onClick={() => edit(true)}>
              <Plus size={16} /> Новый стиль
            </button>
            {!selected.builtin && (
              <>
                <button disabled={locked || Boolean(draft)} onClick={() => edit(false)}>
                  <Pencil size={16} /> Изменить
                </button>
                <button
                  disabled={locked || Boolean(draft) || selected.id === catalog.activeSkinId}
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
                if (locked) return;
                const result = await request(
                  draft.id ? `/admin-api/skins/${draft.id}` : '/admin-api/skins',
                  {
                    method: draft.id ? 'PATCH' : 'POST',
                    body: JSON.stringify({
                      name: draft.name.trim(),
                      palette: draft.palette,
                      artwork: draft.artwork,
                      design: draft.design,
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
                  disabled={locked}
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
                  disabled={locked}
                  onChange={(event) => setDraft({ ...draft, name: event.target.value })}
                />
              </label>
              <label className={styles.name}>
                Рисунок
                <select
                  aria-label="Рисунок стиля"
                  value={draft.artwork ?? ''}
                  disabled={locked}
                  onChange={(event) =>
                    setDraft({
                      ...draft,
                      artwork: event.target.value === 'nocturne' ? 'nocturne' : undefined,
                      design: undefined,
                    })
                  }
                >
                  <option value="">
                    {draft.design ? 'Редактируемая композиция' : 'Без рисунка'}
                  </option>
                  <option value="nocturne">Ноктюрн — небесный атлас</option>
                </select>
              </label>
              <div className={styles.colors}>
                {fieldGroups.map(([group, title]) => (
                  <fieldset
                    key={group}
                    className={group === 'board' ? styles.environment : undefined}
                  >
                    <legend>{title}</legend>
                    <div className={styles.groupFields}>
                      {fields
                        .filter(([part]) => part === group)
                        .map(([part, key, label]) => (
                          <label key={label}>
                            <input
                              type="color"
                              aria-label={label}
                              value={String(Reflect.get(draft.palette[part], key))}
                              disabled={locked}
                              onChange={(event) =>
                                setDraft({
                                  ...draft,
                                  palette: {
                                    ...draft.palette,
                                    [part]: { ...draft.palette[part], [key]: event.target.value },
                                  },
                                })
                              }
                            />
                            <span>
                              {group === 'board'
                                ? label
                                : key === 'body'
                                  ? 'Корпус'
                                  : key === 'cap'
                                    ? 'Верх'
                                    : 'Метка'}
                            </span>
                          </label>
                        ))}
                      {group === 'board' &&
                        (
                          [
                            ['room', 'Цвет комнаты', 'Комната'],
                            ['accent', 'Цвет подсветки', 'Подсветка и победа'],
                          ] as const
                        ).map(([key, label, text]) => (
                          <label key={key}>
                            <input
                              type="color"
                              aria-label={label}
                              value={draft.palette[key]}
                              disabled={locked}
                              onChange={(event) =>
                                setDraft({
                                  ...draft,
                                  palette: { ...draft.palette, [key]: event.target.value },
                                })
                              }
                            />
                            <span>{text}</span>
                          </label>
                        ))}
                    </div>
                  </fieldset>
                ))}
              </div>
              <section className={styles.composition} aria-label="Композиция стиля">
                <div className={styles.editorHeading}>
                  <h2>Композиция</h2>
                  {draft.design && (
                    <button
                      type="button"
                      disabled={locked}
                      aria-label="Удалить композицию"
                      onClick={() => setDraft({ ...draft, design: undefined })}
                    >
                      <Trash2 size={15} />
                    </button>
                  )}
                </div>
                <div className={styles.templates}>
                  {!draft.design && (
                    <button
                      type="button"
                      disabled={locked}
                      onClick={() =>
                        setDraft({
                          ...draft,
                          artwork: undefined,
                          design: blankDesign(draft.palette.accent),
                        })
                      }
                    >
                      <Plus size={15} />
                      Создать композицию
                    </button>
                  )}
                  <button
                    type="button"
                    disabled={locked}
                    data-testid="skin-design-preset"
                    onClick={() => {
                      const template = catalog.skins.find((skin) => skin.id === 'nocturne');
                      setDraft({
                        ...draft,
                        artwork: undefined,
                        palette: template ? structuredClone(template.palette) : draft.palette,
                        design: nocturneDesign(),
                      });
                    }}
                  >
                    <Palette size={15} />
                    Редактируемый Ноктюрн
                  </button>
                  <button
                    type="button"
                    disabled={locked}
                    data-testid="pickmi-design-preset"
                    onClick={() => {
                      const template = catalog.skins.find((skin) => skin.id === 'pickmi');
                      setDraft({
                        ...draft,
                        artwork: undefined,
                        palette: template ? structuredClone(template.palette) : draft.palette,
                        design: pickmiDesign(),
                      });
                    }}
                  >
                    <Palette size={15} />
                    Пикми
                  </button>
                  <button
                    type="button"
                    disabled={locked}
                    data-testid="anime-design-preset"
                    onClick={() => {
                      const template = catalog.skins.find((skin) => skin.id === 'sakura-nocturne');
                      setDraft({
                        ...draft,
                        artwork: undefined,
                        palette: template ? structuredClone(template.palette) : draft.palette,
                        design: animeDesign(),
                      });
                    }}
                  >
                    <Palette size={15} />
                    Лунная сакура
                  </button>
                </div>
                {draft.design && (
                  <SkinDesignEditor
                    design={draft.design}
                    disabled={busy}
                    onBusyChange={setUploading}
                    onUnauthorized={onUnauthorized}
                    onChange={(design) =>
                      setDraft((current) =>
                        current ? { ...current, artwork: undefined, design } : null,
                      )
                    }
                  />
                )}
              </section>
              <button className={styles.primary} disabled={locked}>
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
              />
            </Suspense>
          </div>
          <button
            className={styles.primary}
            disabled={!loaded || locked || Boolean(draft) || selected.id === catalog.activeSkinId}
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
