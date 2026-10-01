import { Component, type ErrorInfo, type ReactNode } from 'react';
export class ErrorBoundary extends Component<
  { children: ReactNode; onError?: () => void },
  { error: boolean }
> {
  state = { error: false };
  static getDerivedStateFromError() {
    return { error: true };
  }
  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('FOUR³ rendering failed', error, info);
    this.props.onError?.();
  }
  render() {
    if (this.state.error)
      return (
        <div style={{ padding: 32, textAlign: 'center', margin: 'auto' }} role="alert">
          <h2>Не удалось открыть 3D-поле</h2>
          <p>Проверьте поддержку WebGL и аппаратное ускорение в браузере.</p>
          <button onClick={() => window.location.reload()}>Попробовать снова</button>
        </div>
      );
    return this.props.children;
  }
}
