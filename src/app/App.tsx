import { useEffect, useState } from 'react';
import { isTauri } from '@tauri-apps/api/core';
import { getRuntimeInfo, type RuntimeInfo } from '../lib/ipc/runtime';

type Connection =
  | { status: 'connecting' }
  | { status: 'connected'; info: RuntimeInfo }
  | { status: 'unavailable'; message: string };

export function App() {
  const [attempt, setAttempt] = useState(0);
  const [connection, setConnection] = useState<Connection>(() =>
    isTauri()
      ? { status: 'connecting' }
      : {
          status: 'unavailable',
          message:
            'Prévia no navegador. Abra o app desktop para conectar ao Rust.',
        },
  );

  useEffect(() => {
    let active = true;
    if (!isTauri()) return;
    void getRuntimeInfo().then(
      (info) => {
        if (active) setConnection({ status: 'connected', info });
      },
      (error: unknown) => {
        if (active)
          setConnection({
            status: 'unavailable',
            message: `Não foi possível conectar: ${String(error)}`,
          });
      },
    );
    return () => {
      active = false;
    };
  }, [attempt]);

  return (
    <main className="foundation">
      <header className="app-header">
        <span className="brand-mark" aria-hidden="true">
          ◈
        </span>
        <strong>Den</strong>
      </header>
      <section className="connection-card" aria-labelledby="welcome-title">
        <p className="eyebrow">React + Tauri</p>
        <h1 id="welcome-title">O próximo workspace começa aqui.</h1>
        <p className="description">
          A fundação está pronta para receber suas conversas, ferramentas e
          projetos.
        </p>
        <div className="connection-status" role="status" aria-live="polite">
          {connection.status === 'connecting' && (
            <p>Conectando ao app desktop…</p>
          )}
          {connection.status === 'unavailable' && <p>{connection.message}</p>}
          {connection.status === 'connected' && (
            <>
              <p className="connected">✓ Conectado ao Rust</p>
              <dl>
                <div>
                  <dt>Aplicativo</dt>
                  <dd>
                    {connection.info.appName} {connection.info.appVersion}
                  </dd>
                </div>
                <div>
                  <dt>Plataforma</dt>
                  <dd>
                    {connection.info.platform} · {connection.info.architecture}
                  </dd>
                </div>
                <div>
                  <dt>Protocolo</dt>
                  <dd>IPC v{connection.info.ipcVersion}</dd>
                </div>
              </dl>
            </>
          )}
        </div>
        <button
          type="button"
          disabled={connection.status === 'connecting'}
          onClick={() => {
            if (isTauri()) setConnection({ status: 'connecting' });
            setAttempt((value) => value + 1);
          }}
        >
          Verificar conexão
        </button>
      </section>
    </main>
  );
}
