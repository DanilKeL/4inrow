import { useCallback, useEffect, useId, useRef, useState } from 'react';
import {
  Activity,
  ArrowDownToLine,
  ArrowUpRight,
  BarChart3,
  CheckCircle2,
  Clock3,
  Cpu,
  Globe2,
  RefreshCw,
  Search,
  UsersRound,
} from 'lucide-react';
import type {
  AnalyticsDashboard as Dashboard,
  AnalyticsFilter,
  AnalyticsMode,
} from '../network/analyticsTypes';
import styles from './AnalyticsDashboard.module.css';

const number = new Intl.NumberFormat('ru-RU');
const modeNames: Record<AnalyticsMode, string> = {
  ranked: 'Рейтинговая игра',
  ai: 'Против AI',
  level: 'Уровни',
  lobby: 'Онлайн-лобби',
  local: 'Вдвоём',
};
const difficultyNames: Record<string, string> = {
  easy: 'Лёгкий',
  medium: 'Средний',
  hard: 'Сложный',
  unknown: 'Без данных о сложности',
};
const deviceNames: Record<string, string> = {
  desktop: 'Компьютер',
  mobile: 'Телефон',
  tablet: 'Планшет',
};
const dateLabel = (date: string) =>
  new Date(`${date}T12:00:00`).toLocaleDateString('ru-RU', { day: 'numeric', month: 'short' });
const time = (seconds: number) =>
  seconds >= 3600
    ? `${(seconds / 3600).toFixed(1)} ч`
    : seconds >= 60
      ? `${Math.round(seconds / 60)} мин`
      : `${Math.round(seconds)} сек`;
const percent = (n: number, total: number) => (total ? `${Math.round((n / total) * 100)}%` : '—');
const today = () => new Date(Date.now() + 3 * 3600000).toISOString().slice(0, 10);
const period = (days: number): AnalyticsFilter => ({
  from: new Date(Date.now() + 3 * 3600000 - (days - 1) * 86400000).toISOString().slice(0, 10),
  to: today(),
  mode: 'all',
  device: 'all',
});

async function request(filter: AnalyticsFilter, signal: AbortSignal) {
  const params = new URLSearchParams({ ...filter });
  const response = await fetch(`/admin-api/analytics?${params}`, {
    credentials: 'same-origin',
    signal,
  });
  const result = (await response.json()) as Dashboard & { error?: string };
  if (!response.ok) throw new Error(result.error ?? 'Не удалось загрузить статистику.');
  return result;
}
function download(data: Dashboard, section: 'daily' | 'players' | 'bots' | 'levels') {
  const escape = (value: unknown) =>
    `"${String(value ?? '')
      .replace(/^[=+@-]/, "'$&")
      .replaceAll('"', '""')}"`;
  let rows: unknown[][];
  if (section === 'players')
    rows = [
      [
        'Игрок',
        'Начато',
        'Завершено',
        'Победы',
        'Поражения',
        'Ничьи',
        'AI',
        'Уровни',
        'Рейтинг',
        'Лобби',
        'Вдвоём',
      ],
      ...data.players.map((p) => [
        p.username,
        p.games,
        p.completed,
        p.wins,
        p.losses,
        p.draws,
        p.ai,
        p.level,
        p.ranked,
        p.lobby,
        p.local,
      ]),
    ];
  else if (section === 'bots')
    rows = [
      [
        'Сложность',
        'Начато',
        'Завершено',
        'Победы игрока',
        'Поражения игрока',
        'Ничьи',
        'Средние ходы',
        'Средние секунды',
      ],
      ...data.bots.map((b) => [
        difficultyNames[b.difficulty],
        b.started,
        b.completed,
        b.wins,
        b.losses,
        b.draws,
        b.averageMoves,
        b.averageSeconds,
      ]),
    ];
  else if (section === 'levels')
    rows = [
      ['Уровень', 'Попытки', 'Завершено', 'Победы', 'Поражения', 'Минимальные ходы'],
      ...data.levels.map((l) => [l.level, l.started, l.completed, l.wins, l.losses, l.bestMoves]),
    ];
  else
    rows = [
      ['Дата (МСК)', 'Посетители', 'Визиты', 'Начато партий', 'Завершено партий', 'Регистрации'],
      ...data.daily.map((d) => [
        d.date,
        d.visitors,
        d.sessions,
        d.started,
        d.completed,
        d.registrations,
      ]),
    ];
  const url = URL.createObjectURL(
    new Blob(['\uFEFF' + rows.map((r) => r.map(escape).join(';')).join('\r\n')], {
      type: 'text/csv;charset=utf-8',
    }),
  );
  const link = document.createElement('a');
  link.href = url;
  link.download = `four-${section}-${data.filter.from}-${data.filter.to}.csv`;
  link.click();
  URL.revokeObjectURL(url);
}

export default function AnalyticsDashboard({ onUnauthorized }: { onUnauthorized: () => void }) {
  const [filter, setFilter] = useState<AnalyticsFilter>(() => period(30));
  const [data, setData] = useState<Dashboard | null>(null);
  const [tab, setTab] = useState<'overview' | 'bots' | 'players' | 'levels'>('overview');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [revision, setRevision] = useState(0);
  const [query, setQuery] = useState('');
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState<string | null>(null);
  const detailsRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (selected) detailsRef.current?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
  }, [selected]);
  const reload = useCallback(() => setRevision((v) => v + 1), []);
  useEffect(() => {
    const controller = new AbortController();
    setLoading(true);
    setError('');
    void request(filter, controller.signal)
      .then((result) => {
        setData(result);
        setPage(1);
      })
      .catch((reason: unknown) => {
        if (controller.signal.aborted) return;
        const message = reason instanceof Error ? reason.message : 'Нет связи с сервером.';
        if (message === 'Войдите в админ-панель.') onUnauthorized();
        else setError(message);
      })
      .finally(() => {
        if (!controller.signal.aborted) setLoading(false);
      });
    return () => controller.abort();
  }, [filter, revision, onUnauthorized]);
  useEffect(() => {
    const timer = window.setInterval(() => {
      if (document.visibilityState === 'visible') reload();
    }, 60_000);
    return () => window.clearInterval(timer);
  }, [reload]);
  const filteredPlayers =
    data?.players.filter((p) => p.username.toLowerCase().includes(query.toLowerCase())) ?? [];
  const player = data?.players.find((p) => p.username === selected);
  const current =
    data &&
    data.filter.from === filter.from &&
    data.filter.to === filter.to &&
    data.filter.mode === filter.mode &&
    data.filter.device === filter.device;
  const exportSection = tab === 'overview' ? 'daily' : tab;
  return (
    <section className={styles.dashboard} aria-label="Статистика игры" aria-busy={loading}>
      <div className={styles.heading}>
        <div>
          <p className={styles.eyebrow}>АНАЛИТИКА FOUR³</p>
          <h1>Статистика</h1>
          <p className={styles.subtitle}>Посещения, игровые режимы и результаты игроков</p>
        </div>
        <div className={styles.actions}>
          {data && (
            <span className={styles.updated}>
              <i />
              Обновлено{' '}
              {new Date(data.generatedAt).toLocaleTimeString('ru-RU', {
                hour: '2-digit',
                minute: '2-digit',
              })}
            </span>
          )}
          <button onClick={reload} disabled={loading} aria-label="Обновить статистику">
            <RefreshCw size={17} className={loading ? styles.spinning : ''} />
          </button>
          <button
            onClick={() => data && download(data, exportSection)}
            disabled={!current || loading}
          >
            <ArrowDownToLine size={17} />
            CSV
          </button>
        </div>
      </div>
      <div className={styles.filters}>
        <div className={styles.presets}>
          {[7, 30, 90].map((days) => (
            <button
              key={days}
              aria-pressed={filter.from === period(days).from && filter.to === today()}
              onClick={() =>
                setFilter({ ...period(days), mode: filter.mode, device: filter.device })
              }
            >
              {days} дней
            </button>
          ))}
        </div>
        <div className={styles.dates}>
          <label>
            С
            <input
              aria-label="Начало периода"
              type="date"
              max={filter.to}
              value={filter.from}
              onChange={(e) => e.target.value && setFilter({ ...filter, from: e.target.value })}
            />
          </label>
          <label>
            По
            <input
              aria-label="Конец периода"
              type="date"
              min={filter.from}
              max={today()}
              value={filter.to}
              onChange={(e) => e.target.value && setFilter({ ...filter, to: e.target.value })}
            />
          </label>
        </div>
        <select
          aria-label="Режим аналитики"
          value={filter.mode}
          onChange={(e) =>
            setFilter({ ...filter, mode: e.target.value as AnalyticsFilter['mode'] })
          }
        >
          <option value="all">Все режимы</option>
          {Object.entries(modeNames).map(([value, name]) => (
            <option value={value} key={value}>
              {name}
            </option>
          ))}
        </select>
        <select
          aria-label="Устройство аналитики"
          value={filter.device}
          onChange={(e) =>
            setFilter({ ...filter, device: e.target.value as AnalyticsFilter['device'] })
          }
        >
          <option value="all">Все устройства</option>
          {Object.entries(deviceNames).map(([value, name]) => (
            <option value={value} key={value}>
              {name}
            </option>
          ))}
        </select>
      </div>
      <nav className={styles.tabs} aria-label="Разделы статистики">
        {(
          [
            ['overview', 'Обзор'],
            ['bots', 'Боты'],
            ['players', 'Игроки'],
            ['levels', 'Уровни'],
          ] as const
        ).map(([key, label]) => (
          <button
            key={key}
            aria-current={tab === key ? 'page' : undefined}
            onClick={() => setTab(key)}
          >
            {label}
          </button>
        ))}
      </nav>
      {error && (
        <div className={styles.error} role="alert">
          {error}
          <button onClick={reload}>Повторить</button>
        </div>
      )}
      {!data && loading && (
        <div className={styles.empty}>
          <RefreshCw className={styles.spinning} />
          <p>Загружаем статистику…</p>
        </div>
      )}
      {data && (
        <div className={`${styles.body} ${!current ? styles.stale : ''}`}>
          {tab === 'overview' && (
            <>
              <div className={styles.metrics}>
                <Metric
                  icon={<UsersRound size={19} />}
                  label="Уникальные посетители"
                  value={number.format(data.summary.visitors)}
                  detail={
                    <Change
                      value={data.summary.visitors}
                      previous={data.summary.previousVisitors}
                    />
                  }
                />
                <Metric
                  icon={<Globe2 size={19} />}
                  label="Визиты"
                  value={number.format(data.summary.sessions)}
                  detail={`${number.format(data.summary.returningVisitors)} вернувшихся посетителей`}
                />
                <Metric
                  icon={<BarChart3 size={19} />}
                  label="Начато партий"
                  value={number.format(data.summary.started)}
                  detail={
                    <Change value={data.summary.started} previous={data.summary.previousStarted} />
                  }
                />
                <Metric
                  icon={<CheckCircle2 size={19} />}
                  label="Завершено партий"
                  value={number.format(data.summary.completed)}
                  detail={`${percent(data.summary.completed, data.summary.started)} от начатых`}
                />
              </div>
              <div className={styles.secondary}>
                <span>
                  <Activity size={16} />
                  <strong>{data.summary.activeNow}</strong> на сайте сейчас
                </span>
                <span>
                  <Clock3 size={16} />
                  <strong>{time(data.summary.averageActiveSeconds)}</strong> активное время визита
                </span>
                <span>
                  <strong>{time(data.summary.averageGameSeconds)}</strong> средняя партия
                </span>
                <span>
                  <strong>{data.summary.abandoned}</strong> прервано ·{' '}
                  <strong>{data.summary.unfinished}</strong> без результата
                </span>
              </div>
              <div className={styles.overviewGrid}>
                <Panel
                  title="Активность по дням"
                  subtitle="Посетители и начатые партии · время Москвы"
                  className={styles.chartPanel}
                >
                  <ActivityChart rows={data.daily} />
                </Panel>
                <Panel title="Игровые режимы" subtitle="Доля от всех начатых партий">
                  <div className={styles.modeList}>
                    {data.modes.map((m, i) => (
                      <div key={m.mode}>
                        <div className={styles.split}>
                          <span>
                            <i style={{ background: colors[i] }} />
                            {modeNames[m.mode]}
                          </span>
                          <strong>
                            {number.format(m.started)}
                            <small>{percent(m.started, data.summary.started)}</small>
                          </strong>
                        </div>
                        <div className={styles.track}>
                          <div
                            style={{
                              width: `${data.summary.started ? (m.started / data.summary.started) * 100 : 0}%`,
                              background: colors[i],
                            }}
                          />
                        </div>
                        <small>
                          {m.completed} завершено · {time(m.averageSeconds)} в среднем
                        </small>
                      </div>
                    ))}
                  </div>
                </Panel>
              </div>
              <div className={styles.threeGrid}>
                <Panel title="Устройства" subtitle="По визитам">
                  <Breakdown
                    rows={data.devices.map((d) => ({ ...d, name: deviceNames[d.name] ?? d.name }))}
                  />
                </Panel>
                <Panel title="Браузеры" subtitle="По визитам">
                  <Breakdown rows={data.browsers} />
                </Panel>
                <Panel
                  title="Источники переходов"
                  subtitle="Домен источника; прямые и внутренние входы объединены"
                >
                  <Breakdown rows={data.sources} />
                </Panel>
              </div>
              <Panel title="Аккаунты и участие" subtitle="Регистрации за период и состав игроков">
                <div className={styles.accountStats}>
                  {[
                    ['Всего аккаунтов', data.accounts.total],
                    ['Новых за период', data.accounts.new],
                    ['Email подтверждён', data.accounts.verified],
                    ['Заблокировано', data.accounts.blocked],
                    ['Аккаунтов играло', data.summary.registeredPlayers],
                    ['Гостей играло', data.summary.guestPlayers],
                  ].map(([label, value]) => (
                    <div key={label}>
                      <strong>{number.format(Number(value))}</strong>
                      <span>{label}</span>
                    </div>
                  ))}
                </div>
              </Panel>
            </>
          )}
          {tab === 'bots' && (
            <>
              <div className={styles.sectionIntro}>
                <Cpu size={23} />
                <div>
                  <h2>Игра против ботов</h2>
                  <p>
                    Победы и поражения считаются со стороны человека. Уровни вынесены в отдельный
                    раздел.
                  </p>
                </div>
              </div>
              <div className={styles.threeGrid}>
                {['easy', 'medium', 'hard'].map((difficulty) => {
                  const b = data.bots.find((b) => b.difficulty === difficulty);
                  const completed = b?.completed ?? 0;
                  return (
                    <Panel
                      key={difficulty}
                      title={`${difficultyNames[difficulty]} бот`}
                      subtitle={`${number.format(b?.started ?? 0)} начатых партий`}
                    >
                      <div className={styles.botScore}>
                        <strong>{percent(b?.wins ?? 0, completed)}</strong>
                        <span>побед игрока</span>
                      </div>
                      <ResultBar
                        wins={b?.wins ?? 0}
                        losses={b?.losses ?? 0}
                        draws={b?.draws ?? 0}
                      />
                      <div className={styles.resultNumbers}>
                        <span>
                          <i className={styles.winDot} />
                          {b?.wins ?? 0} побед
                        </span>
                        <span>
                          <i className={styles.lossDot} />
                          {b?.losses ?? 0} поражений
                        </span>
                        <span>
                          <i className={styles.drawDot} />
                          {b?.draws ?? 0} ничьих
                        </span>
                      </div>
                      <div className={styles.botMeta}>
                        <span>
                          Завершено<strong>{completed}</strong>
                        </span>
                        <span>
                          Средняя длительность<strong>{time(b?.averageSeconds ?? 0)}</strong>
                        </span>
                        <span>
                          Ходов человека в среднем
                          <strong>{completed ? (b?.averageMoves ?? 0).toFixed(1) : '—'}</strong>
                        </span>
                      </div>
                    </Panel>
                  );
                })}
              </div>
              {data.bots.some((b) => b.difficulty === 'unknown') && (
                <p className={styles.info}>
                  В выбранном периоде {data.bots.find((b) => b.difficulty === 'unknown')?.completed}{' '}
                  старых партий против AI без записанной сложности. Они входят в общую статистику,
                  но не в сравнение ботов.
                </p>
              )}
              <Panel
                title="Игроки против AI"
                subtitle="Нажмите на строку, чтобы увидеть результаты по каждой сложности"
              >
                <PlayerTable
                  players={filteredPlayers.filter((p) => p.ai > 0)}
                  onSelect={setSelected}
                  botOnly
                />
              </Panel>
            </>
          )}
          {tab === 'players' && (
            <>
              <div className={styles.playerToolbar}>
                <div>
                  <h2>Активность игроков</h2>
                  <p>До 200 самых активных аккаунтов за выбранный период</p>
                </div>
                <label className={styles.search}>
                  <Search size={17} />
                  <input
                    placeholder="Найти игрока"
                    aria-label="Поиск в статистике"
                    value={query}
                    onChange={(e) => {
                      setQuery(e.target.value);
                      setPage(1);
                    }}
                  />
                </label>
              </div>
              <Panel
                title="Игровая активность"
                subtitle="Победы и поражения: AI, уровни и онлайн; режим «Вдвоём» исключён"
              >
                <PlayerTable
                  players={filteredPlayers.slice((page - 1) * 25, page * 25)}
                  onSelect={setSelected}
                />
                <div className={styles.pagination}>
                  <span>{filteredPlayers.length} игроков</span>
                  <button disabled={page === 1} onClick={() => setPage((p) => p - 1)}>
                    Назад
                  </button>
                  <span>
                    {page} / {Math.max(1, Math.ceil(filteredPlayers.length / 25))}
                  </span>
                  <button
                    disabled={page * 25 >= filteredPlayers.length}
                    onClick={() => setPage((p) => p + 1)}
                  >
                    Далее
                  </button>
                </div>
              </Panel>
            </>
          )}
          {tab === 'levels' && (
            <>
              <div className={styles.sectionIntro}>
                <BarChart3 size={23} />
                <div>
                  <h2>Прохождение уровней</h2>
                  <p>
                    Попытки, победы и число ходов. Повторные прохождения считаются отдельными
                    попытками.
                  </p>
                </div>
              </div>
              <Panel title="Все уровни" subtitle="Доля побед рассчитана по завершённым попыткам">
                <div className={styles.tableScroll}>
                  <table>
                    <thead>
                      <tr>
                        <th>Уровень</th>
                        <th>Попытки</th>
                        <th>Завершено</th>
                        <th>Победы</th>
                        <th>Поражения</th>
                        <th>Побед %</th>
                        <th>Рекорд ходов</th>
                      </tr>
                    </thead>
                    <tbody>
                      {Array.from({ length: 40 }, (_, i) => {
                        const l = data.levels.find((l) => l.level === i + 1);
                        return (
                          <tr key={i}>
                            <td>
                              <strong>{String(i + 1).padStart(2, '0')}</strong>
                            </td>
                            <td>{l?.started ?? 0}</td>
                            <td>{l?.completed ?? 0}</td>
                            <td className={styles.winText}>{l?.wins ?? 0}</td>
                            <td>{l?.losses ?? 0}</td>
                            <td>{percent(l?.wins ?? 0, l?.completed ?? 0)}</td>
                            <td>{l?.bestMoves ?? '—'}</td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>
              </Panel>
            </>
          )}
          {player && (
            <div ref={detailsRef}>
              <Panel
                title={player.username}
                subtitle="Результаты против ботов по сложности"
                className={styles.selectedPlayer}
              >
                <button className={styles.closeDetails} onClick={() => setSelected(null)}>
                  Закрыть
                </button>
                <div className={styles.threeGrid}>
                  {['easy', 'medium', 'hard'].map((d) => {
                    const b = player.bots.find((b) => b.difficulty === d);
                    return (
                      <div className={styles.playerBot} key={d}>
                        <h3>{difficultyNames[d]}</h3>
                        <ResultBar
                          wins={b?.wins ?? 0}
                          losses={b?.losses ?? 0}
                          draws={b?.draws ?? 0}
                        />
                        <p>
                          {b?.wins ?? 0} побед · {b?.losses ?? 0} поражений · {b?.draws ?? 0} ничьих
                        </p>
                      </div>
                    );
                  })}
                </div>
              </Panel>
            </div>
          )}
          <footer className={styles.methodology}>
            <p>
              Сбор посещений и подробных событий начат{' '}
              {new Date(data.collectionStartedAt).toLocaleDateString('ru-RU')}. Завершённые партии
              аккаунтов из прежней базы включены в общие показатели. Один онлайн-матч учитывается
              один раз; у каждого участника — собственный результат.
            </p>
            <p>
              Посетитель — браузер с сохранённым идентификатором; визит обновляется после 30 минут
              отсутствия. Активное время учитывает видимую вкладку. «Без результата» — текущие или
              незавершённые партии. Офлайн-результаты передаёт клиент, онлайн фиксирует сервер.
              Фильтр режима применяется к партиям; фильтр устройства — к визитам и партиям с
              известным устройством.
            </p>
          </footer>
        </div>
      )}
    </section>
  );
}
const colors = ['#2955e7', '#8b6ee8', '#1c9d8f', '#ebad49', '#9aa5b9'];
function Panel({
  title,
  subtitle,
  children,
  className = '',
}: {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <section className={`${styles.panel} ${className}`}>
      <div className={styles.panelHeading}>
        <h2>{title}</h2>
        {subtitle && <p>{subtitle}</p>}
      </div>
      {children}
    </section>
  );
}
function Metric({
  icon,
  label,
  value,
  detail,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
  detail: React.ReactNode;
}) {
  return (
    <article className={styles.metric}>
      <div>
        <span>{label}</span>
        {icon}
      </div>
      <strong>{value}</strong>
      <small>{detail}</small>
    </article>
  );
}
function Change({ value, previous }: { value: number; previous: number }) {
  if (!previous) return <>Предыдущий период: {previous}</>;
  const delta = ((value - previous) / previous) * 100;
  return (
    <>
      <span className={delta >= 0 ? styles.positive : styles.negative}>
        <ArrowUpRight size={13} />
        {delta > 0 ? '+' : ''}
        {delta.toFixed(1)}%
      </span>{' '}
      к предыдущему периоду
    </>
  );
}
function ResultBar({ wins, losses, draws }: { wins: number; losses: number; draws: number }) {
  const total = wins + losses + draws;
  return (
    <div
      className={styles.resultBar}
      aria-label={`${wins} побед, ${losses} поражений, ${draws} ничьих`}
    >
      <span style={{ width: `${total ? (wins / total) * 100 : 0}%` }} />
      <span style={{ width: `${total ? (losses / total) * 100 : 0}%` }} />
      <span style={{ width: `${total ? (draws / total) * 100 : 0}%` }} />
    </div>
  );
}
function Breakdown({ rows }: { rows: Dashboard['devices'] }) {
  const total = rows.reduce((n, r) => n + r.sessions, 0);
  if (!total) return <div className={styles.emptySmall}>Посещений за этот период пока нет</div>;
  return (
    <div className={styles.breakdown}>
      {rows.map((r, i) => (
        <div key={r.name}>
          <div className={styles.split}>
            <span>{r.name}</span>
            <strong>
              {number.format(r.sessions)}
              <small>{percent(r.sessions, total)}</small>
            </strong>
          </div>
          <div className={styles.track}>
            <div
              style={{
                width: `${(r.sessions / total) * 100}%`,
                background: colors[i % colors.length],
              }}
            />
          </div>
        </div>
      ))}
    </div>
  );
}
function PlayerTable({
  players,
  onSelect,
  botOnly = false,
}: {
  players: Dashboard['players'];
  onSelect: (name: string) => void;
  botOnly?: boolean;
}) {
  if (!players.length)
    return <div className={styles.emptySmall}>За этот период игровых данных нет</div>;
  return (
    <div className={styles.tableScroll}>
      <table>
        <thead>
          <tr>
            <th>Игрок</th>
            {!botOnly && (
              <>
                <th>Начато</th>
                <th>Любимый режим</th>
              </>
            )}
            <th>AI</th>
            {!botOnly && (
              <>
                <th>Уровни</th>
                <th>Рейтинг</th>
                <th>Лобби</th>
                <th>Вдвоём</th>
              </>
            )}
            <th>Победы</th>
            <th>Поражения</th>
            <th>Побед %</th>
          </tr>
        </thead>
        <tbody>
          {players.map((p) => {
            const wins = botOnly ? p.bots.reduce((n, b) => n + b.wins, 0) : p.wins,
              losses = botOnly ? p.bots.reduce((n, b) => n + b.losses, 0) : p.losses,
              draws = botOnly ? p.bots.reduce((n, b) => n + b.draws, 0) : p.draws;
            return (
              <tr key={p.username}>
                <td>
                  <button className={styles.playerName} onClick={() => onSelect(p.username)}>
                    {p.username}
                    <ArrowUpRight size={14} />
                  </button>
                </td>
                {!botOnly && (
                  <>
                    <td>{p.games}</td>
                    <td>{modeNames[p.favoriteMode]}</td>
                  </>
                )}
                <td>{p.ai}</td>
                {!botOnly && (
                  <>
                    <td>{p.level}</td>
                    <td>{p.ranked}</td>
                    <td>{p.lobby}</td>
                    <td>{p.local}</td>
                  </>
                )}
                <td className={styles.winText}>{wins}</td>
                <td>{losses}</td>
                <td>{percent(wins, wins + losses + draws)}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
function ActivityChart({ rows }: { rows: Dashboard['daily'] }) {
  const id = useId().replaceAll(':', '');
  const [hover, setHover] = useState<number | null>(null);
  const max = Math.max(4, ...rows.flatMap((r) => [r.visitors, r.started]));
  const top = Math.ceil(max / 4) * 4;
  // Keep plot math explicit to make axes and the hover marker use identical scales.
  const x = (i: number) => 48 + (i * 720) / Math.max(1, rows.length - 1);
  const path = (key: 'visitors' | 'started') =>
    rows.map((r, i) => `${i ? 'L' : 'M'}${x(i)},${210 - (r[key] / top) * 180}`).join(' ');
  const area = `${path('visitors')} L${x(rows.length - 1)},210 L48,210 Z`;
  const hovered = hover === null ? null : rows[hover];
  return (
    <div className={styles.chart}>
      <div className={styles.legend}>
        <span>
          <i style={{ background: colors[0] }} />
          Посетители
        </span>
        <span>
          <i style={{ background: colors[2] }} />
          Начато партий
        </span>
        {hovered && (
          <strong>
            {dateLabel(hovered.date)} · {hovered.visitors} посетителей · {hovered.started} партий
          </strong>
        )}
      </div>
      <svg
        viewBox="0 0 800 245"
        role="img"
        aria-label="График посещений и начатых партий"
        onMouseLeave={() => setHover(null)}
        onPointerMove={(e) => {
          const box = e.currentTarget.getBoundingClientRect();
          setHover(
            Math.max(
              0,
              Math.min(
                rows.length - 1,
                Math.round(
                  ((((e.clientX - box.left) / box.width) * 800 - 48) / 720) * (rows.length - 1),
                ),
              ),
            ),
          );
        }}
      >
        <defs>
          <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#2955e7" stopOpacity=".16" />
            <stop offset="100%" stopColor="#2955e7" stopOpacity=".01" />
          </linearGradient>
        </defs>
        {[0, 1, 2, 3, 4].map((i) => (
          <g key={i}>
            <line
              x1="48"
              x2="768"
              y1={210 - i * 45}
              y2={210 - i * 45}
              stroke="#e7eaf0"
              strokeDasharray="4 4"
            />
            <text x="35" y={214 - i * 45} textAnchor="end">
              {number.format((top * i) / 4)}
            </text>
          </g>
        ))}
        <path d={area} fill={`url(#${id})`} />
        <path
          d={path('visitors')}
          fill="none"
          stroke={colors[0]}
          strokeWidth="2.5"
          strokeLinejoin="round"
        />
        <path
          d={path('started')}
          fill="none"
          stroke={colors[2]}
          strokeWidth="2.5"
          strokeLinejoin="round"
        />
        {hover !== null && (
          <>
            <line
              x1={x(hover)}
              x2={x(hover)}
              y1="20"
              y2="210"
              stroke="#b6c2df"
              strokeDasharray="4 4"
            />
            <circle
              cx={x(hover)}
              cy={210 - (rows[hover].visitors / top) * 180}
              r="4"
              fill={colors[0]}
            />
          </>
        )}
        {[0, Math.floor((rows.length - 1) / 2), rows.length - 1].map((i, index) => (
          <text
            key={index}
            x={x(i)}
            y="237"
            textAnchor={index === 0 ? 'start' : index === 2 ? 'end' : 'middle'}
          >
            {dateLabel(rows[i].date)}
          </text>
        ))}
        <desc>
          {rows.map((r) => `${r.date}: ${r.visitors} посетителей, ${r.started} партий`).join('; ')}
        </desc>
      </svg>
    </div>
  );
}
