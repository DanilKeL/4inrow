import { useState } from 'react';
import { createRoot } from 'react-dom/client';
import { flushSync } from 'react-dom';
import GameScene from '../src/scene/GameScene';
import { createGame, replay } from '../src/game/core';
import { tutorialExamples } from '../src/ui/tutorialExamples';

declare global {
  interface Window {
    recordLesson: (index: number) => Promise<{ bytes: number[]; poster: string; mime: string }>;
    lessonReady: boolean;
  }
}
const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
function Renderer() {
  const [game, setGame] = useState(createGame);
  const [reset, setReset] = useState(0);
  const [view, setView] = useState<'perspective' | 'front'>('perspective');
  window.recordLesson = async (index) => {
    const moves = tutorialExamples[index].moves.map(([x, y]) => ({ x, y }));
    flushSync(() => {
      setGame(createGame());
      setReset((value) => value + 1);
      setView(index === 2 || index >= 4 ? 'front' : 'perspective');
    });
    await delay(1000);
    const canvas = document.querySelector('canvas')!;
    const mime = ['video/mp4;codecs=avc1.42001E', 'video/mp4'].find((type) =>
      MediaRecorder.isTypeSupported(type),
    );
    if (!mime) throw new Error('An H.264-capable browser is required to regenerate tutorial MP4s.');
    // Remove empty margins so the board remains legible in a small mobile player.
    const output = document.createElement('canvas');
    output.width = 960;
    output.height = 480;
    const context = output.getContext('2d')!;
    let frame = 0;
    const draw = () => {
      context.drawImage(canvas, 0, 140, 960, 480, 0, 0, 960, 480);
      frame = requestAnimationFrame(draw);
    };
    draw();
    const stream = output.captureStream(30);
    const recorder = new MediaRecorder(stream, { mimeType: mime, videoBitsPerSecond: 2500000 });
    const chunks: BlobPart[] = [];
    recorder.ondataavailable = (e) => {
      if (e.data.size) chunks.push(e.data);
    };
    const stopped = new Promise<Blob>((resolve) => {
      recorder.onstop = () => resolve(new Blob(chunks, { type: mime }));
    });
    recorder.start();
    await delay(600);
    for (let count = 1; count <= moves.length; count++) {
      flushSync(() => setGame(replay(moves, count)));
      await delay(index === 0 ? 1000 : 700);
    }
    await delay(2300);
    // Capture the settled winning position, not an intermediate falling piece.
    const poster = await new Promise<string>((resolve) =>
      requestAnimationFrame(() => resolve(output.toDataURL('image/webp', 0.9))),
    );
    recorder.stop();
    const blob = await stopped;
    stream.getTracks().forEach((track) => track.stop());
    cancelAnimationFrame(frame);
    return { bytes: Array.from(new Uint8Array(await blob.arrayBuffer())), poster, mime };
  };
  return (
    <GameScene
      game={game}
      onPlace={() => {}}
      interactive={false}
      xray={false}
      layers={[0, 1, 2, 3, 4]}
      cameraView={view}
      cameraReset={reset}
      cameraFov={30}
      animations
      hints={false}
      background="#eeeee8"
      onReady={() => {
        window.lessonReady = true;
      }}
    />
  );
}
createRoot(document.getElementById('root')!).render(<Renderer />);
