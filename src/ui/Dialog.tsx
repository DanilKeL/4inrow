import { useEffect, useRef, type ReactNode } from 'react';
import { motion } from 'motion/react';
import { X } from 'lucide-react';
import styles from './UI.module.css';

export function Dialog({
  title,
  children,
  onClose,
  wide = false,
}: {
  title: string;
  children: ReactNode;
  onClose: () => void;
  wide?: boolean;
}) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    const container = ref.current!;
    container.focus({ preventScroll: true });
    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.stopPropagation();
        onClose();
      }
      if (event.key !== 'Tab') return;
      const items = Array.from(
        container.querySelectorAll<HTMLElement>(
          'button:not(:disabled),input,select,[tabindex="0"]',
        ),
      );
      const first = items[0],
        last = items.at(-1);
      if (document.activeElement === container) {
        event.preventDefault();
        (event.shiftKey ? last : first)?.focus();
        return;
      }
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last?.focus();
      }
      if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first?.focus();
      }
    };
    container.addEventListener('keydown', onKey);
    return () => {
      container.removeEventListener('keydown', onKey);
      previous?.focus();
    };
  }, [onClose]);
  return (
    <div
      className={styles.backdrop}
      onPointerDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <motion.div
        ref={ref}
        role="dialog"
        tabIndex={-1}
        aria-modal="true"
        aria-label={title}
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.18 }}
        className={`${styles.dialog} ${wide ? styles.wide : ''}`}
      >
        <div className={styles.dialogHeader}>
          <h2>{title}</h2>
          <button className={styles.iconButton} aria-label="Закрыть" onClick={onClose}>
            <X size={20} />
          </button>
        </div>
        {children}
      </motion.div>
    </div>
  );
}
