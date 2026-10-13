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
  Material,
  Mesh,
  LatheGeometry,
  MeshBasicMaterial,
  MeshStandardMaterial,
  Vector2,
  Vector3,
  type CanvasTexture,
} from 'three';
import type { Line2, LineSegments2, OrbitControls as OrbitControlsImpl } from 'three-stdlib';
import type { GameState, Move, Position } from '../game/core';
import { WIN_FALL_MS, WIN_LINE_MS } from '../game/victoryPresentation';
import { displayedHeight, visibleLineSegments } from './layers';
import {
  rankedSegmentProgress,
  rankedVictoryProgress,
  type RankedVictoryClock,
} from './rankedVictory';
import { activeSkin, type Skin } from '../skins/catalog';
import { designImageIds, type DesignLayer, type SurfaceName } from '../skins/design';
import { getLoadedSkinImage, loadSkinImage, subscribeSkinImages } from '../skins/imageAssets';
import { useAppearance } from '../store/appearanceStore';
import { makeSurfaceTexture, surfaceDrawingSignature } from './skinDesignTextures';
import {
  disposeNocturneTextures,
  makeNocturneTextures,
  planarBoardGeometry,
  type NocturneTextures,
} from './nocturne';

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
  skin?: Skin;
  victoryPresentation?: boolean;
  victoryId?: string;
}

const SPACING = 1.09;
const STEP = 0.5;
const FIRST = 0.365;
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
      getVictoryPresentationState: () => VictoryPresentationState | null;
      getRenderedWinningLines: () => Array<{
        visible: boolean;
        materialVisible: boolean;
        opacity: number;
        start: number[];
        end: number[];
      }>;
    };
  }
}

type VictoryPresentationState = ReturnType<typeof rankedVictoryProgress> & {
  elapsedMs: number;
  renderedFallOffset: number;
  renderedWinningLines: number;
};
type VictoryDiagnostics = RefObject<(() => VictoryPresentationState | null) | null>;

type SkinTextures = Omit<NocturneTextures, 'metal'> & { metal: CanvasTexture | null };
const EMPTY_IMAGES = new Map<string, HTMLImageElement>();

function useSurfaceArtwork(
  surface: SurfaceName,
  signature: string | null,
  images: Map<string, HTMLImageElement>,
) {
  const previousImages = useRef(EMPTY_IMAGES);
  const relevantImages = new Map<string, HTMLImageElement>();
  if (signature) {
    const drawing = JSON.parse(signature) as { layers: DesignLayer[] };
    for (const layer of drawing.layers) {
      if (layer.kind !== 'image') continue;
      const image = images.get(layer.imageId);
      if (image) relevantImages.set(layer.imageId, image);
    }
  }
  if (
    previousImages.current.size !== relevantImages.size ||
    [...relevantImages].some(([id, image]) => previousImages.current.get(id) !== image)
  ) {
    previousImages.current = relevantImages;
  }
  const drawingImages = previousImages.current;
  const texture = useMemo(
    () =>
      signature ? makeSurfaceTexture(surface, signature, (id) => drawingImages.get(id)) : null,
    [surface, signature, drawingImages],
  );
  useEffect(() => () => texture?.dispose(), [texture]);
  return texture;
}

function useSkinArtwork(skin: Skin): SkinTextures | null {
  const imageKey = designImageIds(skin.design).sort().join(',');
  const cached = useMemo(() => {
    const result = new Map<string, HTMLImageElement>();
    for (const id of imageKey.split(',').filter(Boolean)) {
      const image = getLoadedSkinImage(id);
      if (image) result.set(id, image);
    }
    return result;
  }, [imageKey]);
  const [loaded, setLoaded] = useState({ key: '', images: EMPTY_IMAGES });
  useEffect(() => {
    let current = true;
    const ids = imageKey.split(',').filter(Boolean);
    if (!ids.length) {
      setLoaded((previous) =>
        previous.images.size ? { key: '', images: EMPTY_IMAGES } : previous,
      );
      return;
    }
    const requested = new Set(ids);
    const receive = (id: string, image: HTMLImageElement) => {
      if (!current || !requested.has(id)) return;
      setLoaded((previous) => {
        if (!current) return previous;
        const base = previous.key === imageKey ? previous.images : cached;
        if (base.get(id) === image) return previous;
        const next = new Map(base);
        next.set(id, image);
        return { key: imageKey, images: next };
      });
    };
    const unsubscribe = subscribeSkinImages(receive);
    for (const id of ids) {
      const image = getLoadedSkinImage(id);
      if (image) receive(id, image);
    }
    let cursor = 0;
    void Promise.all(
      Array.from({ length: Math.min(4, ids.length) }, async () => {
        while (cursor < ids.length) {
          const id = ids[cursor++];
          try {
            receive(id, await loadSkinImage(id));
          } catch {
            /* Keep the drawing usable offline even if a new image is unavailable. */
          }
        }
      }),
    );
    return () => {
      current = false;
      unsubscribe();
    };
  }, [imageKey, cached]);
  const images = loaded.key === imageKey ? loaded.images : cached;
  const signature = (surface: SurfaceName, color: string) =>
    skin.design ? surfaceDrawingSignature(color, skin.design.surfaces[surface]) : null;
  const board = useSurfaceArtwork('board', signature('board', skin.palette.board.body), images);
  const darkCap = useSurfaceArtwork('darkCap', signature('darkCap', skin.palette.dark.cap), images);
  const darkBody = useSurfaceArtwork(
    'darkBody',
    signature('darkBody', skin.palette.dark.body),
    images,
  );
  const lightCap = useSurfaceArtwork(
    'lightCap',
    signature('lightCap', skin.palette.light.cap),
    images,
  );
  const lightBody = useSurfaceArtwork(
    'lightBody',
    signature('lightBody', skin.palette.light.body),
    images,
  );
  const legacy = useMemo(
    () => (!skin.design && skin.artwork === 'nocturne' ? makeNocturneTextures(skin.palette) : null),
    [skin.design, skin.artwork, skin.palette],
  );
  useEffect(() => () => disposeNocturneTextures(legacy), [legacy]);
  return useMemo(
    () =>
      board && darkCap && darkBody && lightCap && lightBody
        ? { board, darkCap, darkBody, lightCap, lightBody, metal: null }
        : legacy,
    [board, darkCap, darkBody, lightCap, lightBody, legacy],
  );
}

function BoardModel({ skin, artwork }: { skin: Skin; artwork: SkinTextures | null }) {
  const { scene } = useGLTF('/models/four-board.glb');
  const { model, materials, geometries } = useMemo(() => {
    const model = scene.clone(true);
    const copies = new Map<Material, Material>();
    const geometries: ReturnType<typeof planarBoardGeometry>[] = [];
    const copy = (material: Material) => {
      if (!copies.has(material)) copies.set(material, material.clone());
      return copies.get(material)!;
    };
    model.traverse((object) => {
      if (object instanceof Mesh) {
        object.material = Array.isArray(object.material)
          ? object.material.map(copy)
          : copy(object.material);
        const surfaceMaterials = Array.isArray(object.material)
          ? object.material
          : [object.material];
        if (surfaceMaterials.some((material) => material.name.startsWith('Porcelain'))) {
          object.geometry = planarBoardGeometry(object.geometry);
          geometries.push(object.geometry);
        }
      }
    });
    const materials = [...copies.values()];
    return {
      model,
      materials: materials.map((material) => ({
        material,
        color: material instanceof MeshStandardMaterial ? material.color.clone() : null,
        roughness: material instanceof MeshStandardMaterial ? material.roughness : 0,
        metalness: material instanceof MeshStandardMaterial ? material.metalness : 0,
      })),
      geometries,
    };
  }, [scene]);
  useLayoutEffect(() => {
    for (const original of materials) {
      const { material } = original;
      if (!(material instanceof MeshStandardMaterial)) continue;
      const mapped = Boolean(material.map);
      const metallicMapped = Boolean(material.metalnessMap);
      if (material.name.startsWith('Porcelain')) {
        material.color.set(artwork ? '#ffffff' : skin.palette.board.body);
        material.map = artwork?.board ?? null;
        material.metalnessMap = artwork?.metal ?? null;
        material.roughness =
          skin.design?.surfaces.board.roughness ?? (artwork ? 0.3 : original.roughness);
        material.metalness =
          skin.design?.surfaces.board.metalness ?? (artwork ? 0.86 : original.metalness);
      }
      if (material.name === 'Satin champagne') {
        material.color.set(skin.palette.board.rim);
        material.metalness = artwork ? 0.85 : original.metalness;
        material.roughness = artwork ? 0.26 : original.roughness;
      }
      if (material.name === 'Anodized graphite' && original.color)
        material.color.copy(artwork ? original.color.clone().set('#101c23') : original.color);
      if (material.name === 'Cobalt enamel') material.color.set(skin.palette.accent);
      if (mapped !== Boolean(material.map) || metallicMapped !== Boolean(material.metalnessMap))
        material.needsUpdate = true;
    }
  }, [materials, skin.palette, skin.design, artwork]);
  useEffect(() => () => materials.forEach(({ material }) => material.dispose()), [materials]);
  useEffect(() => () => geometries.forEach((geometry) => geometry.dispose()), [geometries]);
  // Only the shell owns a UV-mapped copy; the cached GLTF stays unchanged.
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
  const mapped = Boolean(material.map);
  if (material.userData.skinMapped !== mapped) {
    material.userData.skinMapped = mapped;
    material.needsUpdate = true;
  }
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
  skin,
  artwork,
  victoryClock,
  presentationPieceRef,
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
  skin: Skin;
  artwork: SkinTextures | null;
  victoryClock?: RankedVictoryClock | null;
  presentationPieceRef?: RefObject<Group | null>;
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
  const palette = dark ? skin.palette.dark : skin.palette.light;
  const bodyDesign = skin.design?.surfaces[dark ? 'darkBody' : 'lightBody'];
  const capDesign = skin.design?.surfaces[dark ? 'darkCap' : 'lightCap'];
  const decoratedCap = capDesign
    ? capDesign.pattern !== 'none' || capDesign.layers.length > 0
    : Boolean(artwork);
  useLayoutEffect(() => {
    if (!presentationPieceRef) return;
    const piece = group.current;
    presentationPieceRef.current = piece;
    return () => {
      if (presentationPieceRef.current === piece) presentationPieceRef.current = null;
    };
  }, [presentationPieceRef]);
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
    const victoryAge = victoryClock ? performance.now() - victoryClock.startedAt : 0;
    const victory = victoryClock ? rankedVictoryProgress(victoryAge) : null;
    const settledY = pos[1] + (ghost ? 0.045 : 0);
    const introFinished =
      introduction === undefined ||
      !animate ||
      (revealed && introAge.current >= introduction + 0.8);
    if (
      !latest &&
      !winner &&
      (!victory ||
        (victoryAge >= WIN_FALL_MS + WIN_LINE_MS &&
          appliedOpacity.current === opacity * (opacity === 1 ? 0.52 : 1))) &&
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
    const dimming = victory && !winner && opacity === 1 ? 1 - 0.48 * victory.dimProgress : 1;
    const renderedOpacity = transition.value * entranceOpacity * dimming;
    if (appliedOpacity.current !== renderedOpacity) {
      appliedOpacity.current = renderedOpacity;
      for (const material of [bodyMaterial.current, capMaterial.current]) {
        if (!material) continue;
        setMaterialOpacity(material, renderedOpacity);
      }
      if (symbolMaterial.current) symbolMaterial.current.opacity = renderedOpacity * 0.85;
    }
    if (ringMaterial.current)
      ringMaterial.current.opacity = ghost
        ? 0.8
        : renderedOpacity * (winner && victory ? victory.ringProgress : 1);
    if (group.current) {
      const t = age.current;
      const fall =
        latest && animate && !ghost
          ? victory
            ? victory.fallOffset
            : t < 0.27
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
        winner && animate
          ? victory
            ? 0.5 + Math.sin((Math.max(0, victoryAge - WIN_FALL_MS) / 1000) * 1.8) * 0.12
            : 0.6 + Math.sin(state.clock.elapsedTime * 3) * 0.3
          : 0.35;
  });
  return (
    <group ref={group} position={pos} visible={visible && (introduction === undefined || !animate)}>
      <mesh geometry={geometry}>
        <meshStandardMaterial
          ref={bodyMaterial}
          color={artwork ? '#ffffff' : palette.body}
          map={artwork ? (dark ? artwork.darkBody : artwork.lightBody) : null}
          roughness={bodyDesign?.roughness ?? (dark ? 0.34 : 0.48)}
          metalness={bodyDesign?.metalness ?? (dark ? 0.2 : 0.08)}
          onUpdate={(material) =>
            setMaterialOpacity(material, appliedOpacity.current ?? fade.current.value)
          }
        />
      </mesh>
      <mesh position={[0, 0.2505, 0]}>
        <cylinderGeometry args={[0.317, 0.317, 0.009, 40]} />
        <meshStandardMaterial
          ref={capMaterial}
          color={artwork ? '#ffffff' : palette.cap}
          map={artwork ? (dark ? artwork.darkCap : artwork.lightCap) : null}
          roughness={capDesign?.roughness ?? (artwork ? 0.48 : 0.52)}
          metalness={capDesign?.metalness ?? (artwork ? 0.12 : 0)}
          onUpdate={(material) =>
            setMaterialOpacity(material, appliedOpacity.current ?? fade.current.value)
          }
        />
      </mesh>
      <mesh visible={!decoratedCap} rotation={[-Math.PI / 2, 0, 0]} position={[0, 0.258, 0]}>
        {dark ? <circleGeometry args={[0.052, 24]} /> : <ringGeometry args={[0.067, 0.085, 32]} />}
        <meshBasicMaterial
          ref={symbolMaterial}
          color={palette.mark}
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
            color={skin.palette.accent}
            emissive={skin.palette.accent}
            emissiveIntensity={0.35}
            transparent
            depthWrite={false}
            opacity={ghost ? 0.8 : winner && victoryClock ? 0 : opacity}
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
  victoryPresentation,
  victoryDiagnostics,
}: Pick<
  GameSceneProps,
  'cameraView' | 'cameraReset' | 'animations' | 'game' | 'layers' | 'demo' | 'victoryPresentation'
> & {
  victoryDiagnostics: VictoryDiagnostics;
}) {
  const controls = useRef<OrbitControlsImpl>(null);
  const { camera, size, gl, scene } = useThree();
  const destination = useRef<Vector3 | null>(null);
  const targetDestination = useRef(new Vector3(0, 0.25, 0));
  const winningPoints = game.winningLines.flat();
  const winningCenter = winningPoints.length
    ? winningPoints
        .reduce<Vector3>((sum, point) => sum.add(new Vector3(...position(point))), new Vector3())
        .divideScalar(winningPoints.length)
    : null;
  const centerX = winningCenter?.x ?? 0;
  const centerY = winningCenter?.y ?? 0;
  const centerZ = winningCenter?.z ?? 0;
  const hasWinningCenter = winningCenter !== null;
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
    if (game.status !== 'won' || !hasWinningCenter) return;
    targetDestination.current.set(centerX, centerY, centerZ).multiplyScalar(0.42);
    destination.current = camera.position.clone();
  }, [game.status, hasWinningCenter, centerX, centerY, centerZ, camera]);
  useEffect(() => {
    if (!import.meta.env.DEV) return;
    const api = {
      getVictoryPresentationState: () => victoryDiagnostics.current?.() ?? null,
      getRenderedWinningLines: () => {
        const lines: Array<{
          visible: boolean;
          materialVisible: boolean;
          opacity: number;
          start: number[];
          end: number[];
        }> = [];
        scene.traverse((object) => {
          const line = object as Line2;
          if (!line.isLine2) return;
          const start = line.geometry.attributes.instanceStart;
          const end = line.geometry.attributes.instanceEnd;
          lines.push({
            visible: line.visible,
            materialVisible: line.material.visible,
            opacity: line.material.opacity,
            start: [start.getX(0), start.getY(0), start.getZ(0)],
            end: [end.getX(0), end.getY(0), end.getZ(0)],
          });
        });
        return lines;
      },
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
  }, [camera, gl, scene, game.heights, layers, victoryDiagnostics]);
  useFrame((_, delta) => {
    if (!destination.current || !controls.current) return;
    const speed = animations ? 1 - Math.exp(-delta * (victoryPresentation ? 1.8 : 6)) : 1;
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

function WinningLine({
  points,
  color,
  victoryClock,
  segment,
  total,
}: {
  points: Position[];
  color: string;
  victoryClock: RankedVictoryClock | null;
  segment: number;
  total: number;
}) {
  const rendered = useRef<Line2 | LineSegments2>(null);
  const applied = useRef<{
    geometry: Line2['geometry'] | LineSegments2['geometry'];
    progress: number;
  } | null>(null);
  const coordinates = useMemo(
    () =>
      points.map((point) => {
        const value = position(point);
        value[1] += 0.27;
        return value;
      }),
    [points],
  );
  useLayoutEffect(() => {
    const line = rendered.current;
    if (line) {
      line.visible = !victoryClock;
      // Drei forwards JSX visibility to both the object and its material.
      // Keep material visibility enabled while the object controls the reveal.
      line.material.visible = true;
    }
    applied.current = null;
  }, [victoryClock, coordinates]);
  useFrame(() => {
    const line = rendered.current;
    if (!line || !victoryClock) return;
    const { lineProgress } = rankedVictoryProgress(performance.now() - victoryClock.startedAt);
    const progress = rankedSegmentProgress(lineProgress, segment, total);
    if (applied.current?.geometry === line.geometry && applied.current.progress === progress)
      return;
    applied.current = { geometry: line.geometry, progress };
    line.visible = progress > 0;
    if (!line.visible) return;
    const [start, end] = coordinates;
    const endpoint = line.geometry.attributes.instanceEnd;
    endpoint.setXYZ(
      0,
      start[0] + (end[0] - start[0]) * progress,
      start[1] + (end[1] - start[1]) * progress,
      start[2] + (end[2] - start[2]) * progress,
    );
    endpoint.needsUpdate = true;
    line.material.opacity = 0.83 * Math.min(1, progress * 4);
  });
  return (
    <Line
      ref={rendered}
      points={coordinates}
      color={color}
      lineWidth={4}
      transparent
      opacity={0.83}
      depthTest={false}
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
  skin,
  gesture,
  clearHover,
  victoryPresentation,
  victoryId,
  victoryDiagnostics,
}: GameSceneProps & {
  skin: Skin;
  gesture: RefObject<Gesture>;
  clearHover: RefObject<(() => void) | null>;
  victoryDiagnostics: VictoryDiagnostics;
}) {
  const [hover, setHover] = useState<number | null>(null);
  const [invalidColumn, setInvalidColumn] = useState<number | null>(null);
  const invalidTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const { gl, scene } = useThree();
  useEffect(() => {
    clearHover.current = () => setHover(null);
    return () => {
      clearHover.current = null;
    };
  }, [clearHover]);
  const pieceGeometry = useMemo(makePieceGeometry, []);
  const artwork = useSkinArtwork(skin);
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
  const victoryKey =
    animations && !demo
      ? (victoryId ??
        (victoryPresentation && last
          ? `${last.index}-${last.x}-${last.y}-${last.z}-${last.player}`
          : null))
      : null;
  const presentationClock = useMemo(
    () => (victoryKey ? { key: victoryKey, startedAt: performance.now() } : null),
    [victoryKey],
  );
  const victoryClock = victoryPresentation ? presentationClock : null;
  const lastPiece = useRef<Group | null>(null);
  const lastY = last ? position(last)[1] : 0;
  useEffect(() => {
    if (!import.meta.env.DEV || !victoryClock) {
      victoryDiagnostics.current = null;
      return;
    }
    const read = () => {
      const elapsedMs = performance.now() - victoryClock.startedAt;
      let renderedWinningLines = 0;
      scene.traverse((object) => {
        const line = object as Line2;
        if (line.isLine2 && line.visible && line.material.visible && line.material.opacity > 0)
          renderedWinningLines++;
      });
      return {
        ...rankedVictoryProgress(elapsedMs),
        elapsedMs,
        renderedFallOffset: (lastPiece.current?.position.y ?? lastY) - lastY,
        renderedWinningLines,
      };
    };
    victoryDiagnostics.current = read;
    return () => {
      if (victoryDiagnostics.current === read) victoryDiagnostics.current = null;
    };
  }, [victoryClock, victoryDiagnostics, lastY, scene]);
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
      <BoardModel skin={skin} artwork={artwork} />
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
                  color={
                    invalidColumn === i
                      ? '#db584b'
                      : hovered
                        ? skin.palette.accent
                        : skin.palette.board.rim
                  }
                  metalness={0.35}
                  roughness={0.36}
                  emissive={
                    invalidColumn === i ? '#db584b' : hovered ? skin.palette.accent : '#000000'
                  }
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
                <meshBasicMaterial color={skin.palette.board.dot} />
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
          skin={skin}
          artwork={artwork}
          geometry={pieceGeometry}
          latest={!demo && last === move}
          winner={winners.has(`${move.x},${move.y},${move.z}`)}
          visible={layers.includes(move.z)}
          opacity={
            xray
              ? 0.43
              : game.status === 'won' &&
                  !victoryClock &&
                  !winners.has(`${move.x},${move.y},${move.z}`)
                ? 0.52
                : 1
          }
          animate={animations}
          introduction={demo ? 0.45 + (move.x + move.y) * 0.055 + move.z * 0.14 : undefined}
          revealed={revealed}
          victoryClock={victoryClock}
          presentationPieceRef={last === move ? lastPiece : undefined}
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
            skin={skin}
            artwork={artwork}
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
      {game.winningLines.flatMap((source, lineIndex) => {
        // Draw outward from the last chip when it forms an endpoint of the line.
        const endpoint = source.at(-1);
        const line =
          victoryClock &&
          endpoint &&
          last &&
          endpoint.x === last.x &&
          endpoint.y === last.y &&
          endpoint.z === last.z
            ? [...source].reverse()
            : source;
        return visibleLineSegments(line, layers).map((points) => (
          <WinningLine
            key={`${lineIndex}-${points[0].x}-${points[0].y}-${points[0].z}`}
            points={points}
            color={skin.palette.accent}
            victoryClock={victoryClock}
            segment={line.indexOf(points[0])}
            total={line.length - 1}
          />
        ));
      })}
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
  const catalog = useAppearance((state) => state.catalog);
  const skin = props.skin ?? activeSkin(catalog);
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
  const victoryDiagnostics = useRef<(() => VictoryPresentationState | null) | null>(null);
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
          <color attach="background" args={[props.background ?? skin.palette.room]} />
          <ScenePerformance pointerEvents={pointerEvents} onDprChange={setRenderDpr} />
          <ambientLight intensity={0.5} />
          <hemisphereLight args={['#ffffff', '#a4a09a', 1.2]} />
          <directionalLight position={[-4, 9, 3]} intensity={2.4} color="#fff3dc" />
          <directionalLight position={[6, 4, -5]} intensity={1.4} color="#dde7ff" />
          <directionalLight position={[-4, 2, -4]} intensity={0.6} color="#ffffff" />
          <Suspense fallback={null}>
            <Board
              {...props}
              skin={skin}
              gesture={gesture}
              clearHover={clearHover}
              victoryDiagnostics={victoryDiagnostics}
            />
            <SceneReady onReady={props.onReady} />
          </Suspense>
          <CameraRig {...props} victoryDiagnostics={victoryDiagnostics} />
        </Canvas>
      </SceneBoundary>
    </div>
  );
}
