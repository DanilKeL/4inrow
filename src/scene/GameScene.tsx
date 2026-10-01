import {
  Component,
  Suspense,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
  useState,
  type ErrorInfo,
  type ReactNode,
  type RefObject,
} from 'react';
import { Canvas, useFrame, useThree, type ThreeEvent } from '@react-three/fiber';
import { Line, OrbitControls, useGLTF } from '@react-three/drei';
import {
  Group,
  LatheGeometry,
  MeshBasicMaterial,
  MeshStandardMaterial,
  Vector2,
  Vector3,
} from 'three';
import type { OrbitControls as OrbitControlsImpl } from 'three-stdlib';
import type { GameState, Move, Position } from '../game/core';
import { displayedHeight, visibleLineSegments } from './layers';

export interface GameSceneProps {
  game: GameState;
  onPlace: (x: number, y: number) => void;
  interactive: boolean;
  xray: boolean;
  layers: number[];
  cameraView: 'perspective' | 'top' | 'front';
  cameraReset: number;
  animations: boolean;
  hints: boolean;
  demo?: boolean;
  revealed?: boolean;
  onReady?: () => void;
  onError?: () => void;
  background?: string;
  cameraFov?: number;
}

const SPACING = 1.09;
const STEP = 0.5;
const FIRST = 0.365;
const BLUE = '#3661ee';
const MAX_RENDER_PIXELS = 3_000_000;
const position = ({ x, y, z }: Position): [number, number, number] => [
  (x - 2) * SPACING,
  FIRST + z * STEP,
  (y - 2) * SPACING,
];
type Gesture = {
  pointers: Set<number>;
  x: number;
  y: number;
  id: number;
  moved: boolean;
  multiple: boolean;
};

declare global {
  interface Window {
    __fourScene?: {
      getColumnScreenPositions: () => Array<{
        x: number;
        y: number;
        screenX: number;
        screenY: number;
      }>;
    };
  }
}

function BoardModel() {
  const { scene } = useGLTF('/models/four-board.glb');
  const model = useMemo(() => scene.clone(true), [scene]);
  // Geometry and materials belong to useGLTF's cache; scene instances only own their transforms.
  return <primitive object={model} dispose={null} />;
}

function makePieceGeometry() {
  return new LatheGeometry(
    [
      [0, -0.25],
      [0.342, -0.25],
      [0.377, -0.241],
      [0.397, -0.214],
      [0.4, -0.18],
      [0.4, 0.175],
      [0.394, 0.211],
      [0.375, 0.237],
      [0.342, 0.25],
      [0, 0.25],
    ].map(([radius, height]) => new Vector2(radius, height)),
    48,
  );
}

function setMaterialOpacity(material: MeshStandardMaterial, opacity: number) {
  const transparent = opacity < 1;
  if (material.transparent !== transparent) {
    material.transparent = transparent;
    // Three.js compiles the OPAQUE shader define. Updating alpha alone cannot change it.
    material.needsUpdate = true;
  }
  material.opacity = opacity;
  material.depthWrite = !transparent;
}

function Piece({
  move,
  geometry,
  latest,
  winner,
  opacity,
  animate,
  visible = true,
  ghost = false,
  introduction,
  revealed = true,
}: {
  move: Move;
  geometry: LatheGeometry;
  latest: boolean;
  winner: boolean;
  opacity: number;
  animate: boolean;
  visible?: boolean;
  ghost?: boolean;
  introduction?: number;
  revealed?: boolean;
}) {
  const group = useRef<Group>(null);
  const bodyMaterial = useRef<MeshStandardMaterial>(null);
  const capMaterial = useRef<MeshStandardMaterial>(null);
  const symbolMaterial = useRef<MeshBasicMaterial>(null);
  const ringMaterial = useRef<MeshStandardMaterial>(null);
  const fade = useRef({ value: opacity, from: opacity, target: opacity, elapsed: 0.15 });
  const age = useRef(0);
  const introAge = useRef(0);
  const appliedOpacity = useRef<number | null>(null);
  const pos = position(move);
  const dark = move.player === 1;
  useEffect(() => {
    fade.current = {
      value: fade.current.value,
      from: fade.current.value,
      target: opacity,
      elapsed: 0,
    };
  }, [opacity]);
  useFrame((state, delta) => {
    age.current += delta;
    if (revealed) introAge.current += delta;
    const settledY = pos[1] + (ghost ? 0.045 : 0);
    const introFinished =
      introduction === undefined ||
      !animate ||
      (revealed && introAge.current >= introduction + 0.8);
    if (
      !latest &&
      !winner &&
      introFinished &&
      fade.current.elapsed >= 0.15 &&
      appliedOpacity.current !== null &&
      group.current?.visible === visible &&
      Math.abs((group.current?.position.y ?? settledY) - settledY) < 0.0001
    )
      return;
    const introducing = introduction !== undefined && animate;
    const introTime = introAge.current - (introduction ?? 0);
    const introProgress = introducing ? Math.max(0, Math.min(1, introTime / 0.8)) : 1;
    const fadeProgress = Math.min(1, introProgress * 4);
    const entranceOpacity = fadeProgress * fadeProgress * (3 - 2 * fadeProgress);
    const transition = fade.current;
    if (transition.elapsed < 0.15) {
      transition.elapsed = animate ? Math.min(0.15, transition.elapsed + delta) : 0.15;
      transition.value =
        transition.from + (transition.target - transition.from) * (transition.elapsed / 0.15);
    }
    const renderedOpacity = transition.value * entranceOpacity;
    if (appliedOpacity.current !== renderedOpacity) {
      appliedOpacity.current = renderedOpacity;
      for (const material of [bodyMaterial.current, capMaterial.current]) {
        if (!material) continue;
        setMaterialOpacity(material, renderedOpacity);
      }
      if (symbolMaterial.current) symbolMaterial.current.opacity = renderedOpacity * 0.85;
      if (ringMaterial.current) ringMaterial.current.opacity = ghost ? 0.8 : renderedOpacity;
    }
    if (group.current) {
      const t = age.current;
      const fall =
        latest && animate && !ghost
          ? t < 0.27
            ? 2.2 * (1 - (t / 0.27) ** 2)
            : t < 0.41
              ? Math.sin(((t - 0.27) / 0.14) * Math.PI) * 0.085
              : 0
          : 0;
      // A short, decelerating descent lets the menu assemble gently without bouncing.
      const introFall = 0.7 * (1 - introProgress) ** 3;
      group.current.visible = visible && (!introducing || (revealed && introTime >= 0));
      group.current.position.y = pos[1] + fall + introFall + (ghost ? 0.045 : 0);
    }
    if (ringMaterial.current)
      ringMaterial.current.emissiveIntensity =
        winner && animate ? 0.6 + Math.sin(state.clock.elapsedTime * 3) * 0.3 : 0.35;
  });
  return (
    <group ref={group} position={pos} visible={visible && (introduction === undefined || !animate)}>
      <mesh geometry={geometry}>
        <meshStandardMaterial
          ref={bodyMaterial}
          color={dark ? '#24272c' : '#eee4d2'}
          roughness={dark ? 0.34 : 0.48}
          metalness={dark ? 0.2 : 0.08}
          onUpdate={(material) => setMaterialOpacity(material, fade.current.value)}
        />
      </mesh>
      <mesh position={[0, 0.2505, 0]}>
        <cylinderGeometry args={[0.317, 0.317, 0.009, 40]} />
        <meshStandardMaterial
          ref={capMaterial}
          color={dark ? '#24292f' : '#f5edde'}
          roughness={0.52}
          onUpdate={(material) => setMaterialOpacity(material, fade.current.value)}
        />
      </mesh>
      <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.258, 0]}>
        {dark ? <circleGeometry args={[0.052, 24]} /> : <ringGeometry args={[0.067, 0.085, 32]} />}
        <meshBasicMaterial
          ref={symbolMaterial}
          color={dark ? '#858992' : '#969286'}
          transparent
          opacity={opacity * 0.85}
          depthWrite={false}
        />
      </mesh>
      {(latest || winner || ghost) && (
        <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.242, 0]}>
          <torusGeometry args={[0.353, winner ? 0.017 : 0.009, 8, 48]} />
          <meshStandardMaterial
            ref={ringMaterial}
            color={BLUE}
            emissive={BLUE}
            emissiveIntensity={0.35}
            transparent
            depthWrite={false}
            opacity={ghost ? 0.8 : opacity}
          />
        </mesh>
      )}
    </group>
  );
}

function CameraRig({
  cameraView,
  cameraReset,
  animations,
  game,
  layers,
  demo,
}: Pick<GameSceneProps, 'cameraView' | 'cameraReset' | 'animations' | 'game' | 'layers' | 'demo'>) {
  const controls = useRef<OrbitControlsImpl>(null);
  const { camera, size, gl } = useThree();
  const destination = useRef<Vector3 | null>(null);
  const targetDestination = useRef(new Vector3(0, 0.25, 0));
  useEffect(() => {
    const fit = Math.max(1, 0.9 / (size.width / size.height));
    const view =
      cameraView === 'top'
        ? new Vector3(0, 13.7, 0.035)
        : cameraView === 'front'
          ? new Vector3(0, 5.6, 12.8)
          : demo
            ? new Vector3(8.7, 7.25, 9.8)
            : new Vector3(7.4, 9.2, 9.3);
    destination.current = view.multiplyScalar(fit * (demo ? 0.92 : 1));
    targetDestination.current.set(0, 0.25, 0);
    if (!animations) {
      camera.position.copy(destination.current);
      controls.current?.target.copy(targetDestination.current);
      controls.current?.update();
      destination.current = null;
    }
  }, [cameraView, cameraReset, camera, size.width, size.height, animations, demo]);
  useEffect(() => {
    if (game.status !== 'won' || !game.winningLines.length) return;
    const points = game.winningLines.flat();
    const center = points
      .reduce<Vector3>((sum, point) => sum.add(new Vector3(...position(point))), new Vector3())
      .divideScalar(points.length);
    targetDestination.current.copy(center).multiplyScalar(0.42);
    destination.current = camera.position.clone();
  }, [game.status, game.winningLines, camera]);
  useEffect(() => {
    if (!import.meta.env.DEV) return;
    const api = {
      getColumnScreenPositions: () => {
        const bounds = gl.domElement.getBoundingClientRect();
        camera.updateMatrixWorld();
        return game.heights.map((height, i) => {
          const x = i % 5;
          const y = Math.floor(i / 5);
          const visibleHeight = displayedHeight(height, layers);
          const point = new Vector3(
            (x - 2) * SPACING,
            0.13 + visibleHeight * STEP,
            (y - 2) * SPACING,
          ).project(camera);
          return {
            x,
            y,
            screenX: bounds.left + ((point.x + 1) / 2) * bounds.width,
            screenY: bounds.top + ((1 - point.y) / 2) * bounds.height,
          };
        });
      },
    };
    window.__fourScene = api;
    return () => {
      if (window.__fourScene === api) delete window.__fourScene;
    };
  }, [camera, gl, game.heights, layers]);
  useFrame((_, delta) => {
    if (!destination.current || !controls.current) return;
    const speed = animations ? 1 - Math.exp(-delta * 6) : 1;
    camera.position.lerp(destination.current, speed);
    controls.current.target.lerp(targetDestination.current, speed);
    controls.current.update();
    if (
      camera.position.distanceTo(destination.current) < 0.008 &&
      controls.current.target.distanceTo(targetDestination.current) < 0.008
    )
      destination.current = null;
  });
  return (
    <OrbitControls
      ref={controls}
      makeDefault
      target={[0, 0.25, 0]}
      enablePan={false}
      enableDamping
      dampingFactor={0.09}
      rotateSpeed={0.65}
      zoomSpeed={0.65}
      minDistance={7}
      maxDistance={23}
      minPolarAngle={0.001}
      maxPolarAngle={Math.PI / 2.16}
      onStart={() => {
        destination.current = null;
      }}
    />
  );
}

function Board({
  game,
  onPlace,
  interactive,
  xray,
  layers,
  animations,
  hints,
  demo,
  revealed,
  gesture,
  clearHover,
}: GameSceneProps & { gesture: RefObject<Gesture>; clearHover: RefObject<(() => void) | null> }) {
  const [hover, setHover] = useState<number | null>(null);
  const [invalidColumn, setInvalidColumn] = useState<number | null>(null);
  const invalidTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const { gl } = useThree();
  useEffect(() => {
    clearHover.current = () => setHover(null);
    return () => {
      clearHover.current = null;
    };
  }, [clearHover]);
  const pieceGeometry = useMemo(makePieceGeometry, []);
  useEffect(
    () => () => {
      if (invalidTimer.current) clearTimeout(invalidTimer.current);
    },
    [],
  );
  useEffect(
    () => () => {
      pieceGeometry.dispose();
    },
    [pieceGeometry],
  );
  useEffect(() => {
    gl.domElement.style.cursor =
      interactive && hover !== null && game.heights[hover] < 5 ? 'pointer' : 'grab';
    return () => {
      gl.domElement.style.cursor = '';
    };
  }, [hover, interactive, game.heights, gl]);
  const winners = new Set(game.winningLines.flat().map((p) => `${p.x},${p.y},${p.z}`));
  const last = game.history.at(-1);
  const select = (event: ThreeEvent<PointerEvent>, x: number, y: number) => {
    event.stopPropagation();
    const g = gesture.current;
    if (
      !interactive ||
      game.status !== 'playing' ||
      g.moved ||
      g.multiple ||
      g.id !== event.pointerId ||
      event.button !== 0
    )
      return;
    if (Math.hypot(event.clientX - g.x, event.clientY - g.y) > 8) return;
    if (game.heights[x + y * 5] >= 5) {
      setInvalidColumn(x + y * 5);
      if (invalidTimer.current) clearTimeout(invalidTimer.current);
      invalidTimer.current = setTimeout(() => setInvalidColumn(null), 650);
    }
    onPlace(x, y);
    setHover(null);
  };
  return (
    <group>
      <BoardModel />
      {game.heights.map((height, i) => {
        const x = i % 5;
        const y = Math.floor(i / 5);
        const available = height < 5 && game.status === 'playing';
        const hovered = hover === i && interactive && available;
        const pickHeight = 0.13 + displayedHeight(height, layers) * STEP;
        return (
          <group key={i} position={[(x - 2) * SPACING, 0, (y - 2) * SPACING]}>
            {(hovered || invalidColumn === i) && (
              <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.173, 0]}>
                <torusGeometry args={[0.49, 0.01, 8, 64]} />
                <meshStandardMaterial
                  color={invalidColumn === i ? '#db584b' : hovered ? BLUE : '#cbc2b2'}
                  metalness={0.35}
                  roughness={0.36}
                  emissive={invalidColumn === i ? '#db584b' : hovered ? BLUE : '#000000'}
                  emissiveIntensity={0.2}
                />
              </mesh>
            )}
            {invalidColumn === i && (
              <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.13 + height * STEP, 0]}>
                <torusGeometry args={[0.42, 0.025, 8, 40]} />
                <meshBasicMaterial color="#db584b" depthTest={false} />
              </mesh>
            )}
            {height === 0 && (
              <mesh rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.108, 0]}>
                <circleGeometry args={[0.025, 16]} />
                <meshBasicMaterial color="#979992" />
              </mesh>
            )}
            <mesh
              position={[0, pickHeight / 2, 0]}
              onPointerOver={(e) => {
                e.stopPropagation();
                if (!gesture.current.pointers.size) setHover(i);
              }}
              onPointerOut={() => {
                if (!gesture.current.pointers.size) setHover(null);
              }}
              onPointerUp={(e) => select(e, x, y)}
            >
              <cylinderGeometry args={[0.49, 0.49, pickHeight + 0.025, 16]} />
              <meshBasicMaterial transparent opacity={0} depthWrite={false} colorWrite={false} />
            </mesh>
          </group>
        );
      })}
      {game.history.map((move) => (
        <Piece
          key={`${demo ? 'demo' : 'game'}-${move.index}-${move.x}-${move.y}`}
          move={move}
          geometry={pieceGeometry}
          latest={!demo && last === move}
          winner={winners.has(`${move.x},${move.y},${move.z}`)}
          visible={layers.includes(move.z)}
          opacity={
            xray
              ? 0.43
              : game.status === 'won' && !winners.has(`${move.x},${move.y},${move.z}`)
                ? 0.52
                : 1
          }
          animate={animations}
          introduction={demo ? 0.45 + (move.x + move.y) * 0.055 + move.z * 0.14 : undefined}
          revealed={revealed}
        />
      ))}
      {hover !== null &&
        interactive &&
        hints &&
        game.status === 'playing' &&
        layers.includes(game.heights[hover]) &&
        game.heights[hover] < 5 && (
          <Piece
            key={`ghost-${hover}`}
            move={{
              x: hover % 5,
              y: Math.floor(hover / 5),
              z: game.heights[hover],
              player: game.currentPlayer,
              index: -1,
            }}
            geometry={pieceGeometry}
            latest={false}
            winner={false}
            opacity={0.23}
            animate={false}
            ghost
          />
        )}
      {game.winningLines
        .flatMap((line) => visibleLineSegments(line, layers))
        .map((line, index) => (
          <Line
            key={index}
            points={line.map((p) => {
              const value = position(p);
              value[1] += 0.27;
              return value;
            })}
            color={BLUE}
            lineWidth={4}
            transparent
            opacity={0.83}
            depthTest={false}
          />
        ))}
    </group>
  );
}

function SceneFallback() {
  return (
    <div
      role="status"
      style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        height: '100%',
        minHeight: 220,
        padding: 32,
        boxSizing: 'border-box',
      }}
    >
      <div
        style={{
          maxWidth: 320,
          textAlign: 'center',
          color: '#70746c',
          fontSize: 14,
          lineHeight: 1.6,
        }}
      >
        <strong style={{ display: 'block', color: '#272c28', fontSize: 18, marginBottom: 10 }}>
          Не удалось загрузить 3D-поле
        </strong>
        Обновите страницу или откройте игру в браузере с поддержкой WebGL.
      </div>
    </div>
  );
}

class SceneBoundary extends Component<
  { children: ReactNode; onError?: () => void },
  { error: boolean }
> {
  state = { error: false };
  static getDerivedStateFromError() {
    return { error: true };
  }
  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('FOUR³: 3D scene failed to render', error, info.componentStack);
    this.props.onError?.();
  }
  render() {
    if (this.state.error) return <SceneFallback />;
    return this.props.children;
  }
}

// This only mounts when the entire suspended board is ready. Two frames let the
// renderer upload geometry and draw the scene before the loading cover fades.
function SceneReady({ onReady }: { onReady?: () => void }) {
  const frames = useRef(0);
  useFrame(() => {
    if (++frames.current === 2) onReady?.();
  });
  return null;
}

function ScenePerformance({
  pointerEvents,
  onDprChange,
}: {
  pointerEvents: RefObject<((enabled: boolean) => void) | null>;
  onDprChange: (dpr: number) => void;
}) {
  const { size, setEvents } = useThree();
  useLayoutEffect(() => {
    const area = Math.max(1, size.width * size.height);
    const update = () =>
      onDprChange(
        Math.max(1, Math.min(window.devicePixelRatio || 1, 3, Math.sqrt(MAX_RENDER_PIXELS / area))),
      );
    update();
    window.addEventListener('resize', update);
    return () => window.removeEventListener('resize', update);
  }, [size.width, size.height, onDprChange]);
  useEffect(() => {
    pointerEvents.current = (enabled) => setEvents({ enabled });
    return () => {
      pointerEvents.current = null;
    };
  }, [pointerEvents, setEvents]);
  return null;
}

export default function GameScene(props: GameSceneProps) {
  // Canvas reapplies its dpr prop on each render. Keep the measured value here
  // so timer ticks and moves cannot reset the renderer to its initial DPR.
  const [renderDpr, setRenderDpr] = useState(1);
  const gesture = useRef<Gesture>({
    pointers: new Set(),
    x: 0,
    y: 0,
    id: -1,
    moved: false,
    multiple: false,
  });
  const pointerEvents = useRef<((enabled: boolean) => void) | null>(null);
  const clearHover = useRef<(() => void) | null>(null);
  useEffect(() => {
    const finish = (event: PointerEvent) => {
      gesture.current.pointers.delete(event.pointerId);
      if (!gesture.current.pointers.size) pointerEvents.current?.(true);
    };
    window.addEventListener('pointerup', finish, true);
    window.addEventListener('pointercancel', finish, true);
    return () => {
      window.removeEventListener('pointerup', finish, true);
      window.removeEventListener('pointercancel', finish, true);
    };
  }, []);
  return (
    <div
      className="game-scene"
      style={{ width: '100%', height: '100%', touchAction: 'none' }}
      onPointerDownCapture={(event) => {
        const g = gesture.current;
        if (g.pointers.size === 0) {
          g.x = event.clientX;
          g.y = event.clientY;
          g.id = event.pointerId;
          g.moved = false;
          g.multiple = false;
        }
        g.pointers.add(event.pointerId);
        if (g.pointers.size > 1) {
          g.multiple = true;
          g.moved = true;
          clearHover.current?.();
          pointerEvents.current?.(false);
        }
      }}
      onPointerMoveCapture={(event) => {
        const g = gesture.current;
        if (
          g.pointers.size &&
          !g.moved &&
          Math.hypot(event.clientX - g.x, event.clientY - g.y) > 8
        ) {
          g.moved = true;
          clearHover.current?.();
          pointerEvents.current?.(false);
        }
      }}
      onPointerUp={(event) => {
        gesture.current.pointers.delete(event.pointerId);
        if (!gesture.current.pointers.size) pointerEvents.current?.(true);
      }}
      onPointerCancel={(event) => {
        gesture.current.moved = true;
        gesture.current.pointers.delete(event.pointerId);
        if (!gesture.current.pointers.size) pointerEvents.current?.(true);
      }}
      onLostPointerCapture={(event) => {
        gesture.current.pointers.delete(event.pointerId);
        if (!gesture.current.pointers.size) pointerEvents.current?.(true);
      }}
      onPointerLeave={() => {
        gesture.current.moved = true;
        clearHover.current?.();
        if (gesture.current.pointers.size) pointerEvents.current?.(false);
      }}
    >
      <SceneBoundary onError={props.onError}>
        <Canvas
          data-testid="game-canvas"
          dpr={renderDpr}
          camera={{ position: [7.4, 9.2, 9.3], fov: props.cameraFov ?? 35, near: 0.1, far: 100 }}
          gl={{ antialias: true, alpha: true, powerPreference: 'high-performance' }}
          fallback={<SceneFallback />}
        >
          {(props.background || props.demo) && (
            <color attach="background" args={[props.background ?? '#ebeae7']} />
          )}
          <ScenePerformance pointerEvents={pointerEvents} onDprChange={setRenderDpr} />
          <ambientLight intensity={0.5} />
          <hemisphereLight args={['#ffffff', '#a4a09a', 1.2]} />
          <directionalLight position={[-4, 9, 3]} intensity={2.4} color="#fff3dc" />
          <directionalLight position={[6, 4, -5]} intensity={1.4} color="#dde7ff" />
          <directionalLight position={[-4, 2, -4]} intensity={0.6} color="#ffffff" />
          <Suspense fallback={null}>
            <Board {...props} gesture={gesture} clearHover={clearHover} />
            <SceneReady onReady={props.onReady} />
          </Suspense>
          <CameraRig {...props} />
        </Canvas>
      </SceneBoundary>
    </div>
  );
}
