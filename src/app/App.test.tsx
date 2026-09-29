import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { mockIPC } from '@tauri-apps/api/mocks';
import { expect, test, vi } from 'vitest';
import { App } from './App';

test('connects through the runtime command and can retry after a failure', async () => {
  vi.stubGlobal('isTauri', true);
  const command = vi
    .fn()
    .mockRejectedValueOnce('backend indisponível')
    .mockResolvedValue({
      appName: 'Den',
      appVersion: '1.0.0',
      platform: 'macos',
      architecture: 'aarch64',
      ipcVersion: 1,
    });
  mockIPC((name) => {
    expect(name).toBe('runtime_info');
    return command();
  });
  render(<App />);
  expect(
    await screen.findByText('Não foi possível conectar: backend indisponível'),
  ).toBeInTheDocument();
  await userEvent.click(
    screen.getByRole('button', { name: 'Verificar conexão' }),
  );
  expect(await screen.findByText('✓ Conectado ao Rust')).toBeInTheDocument();
  expect(screen.getByText('macos · aarch64')).toBeInTheDocument();
  expect(screen.getByText('IPC v1')).toBeInTheDocument();
  expect(command).toHaveBeenCalledTimes(2);
});

test('explains browser preview without attempting desktop IPC', () => {
  const command = vi.fn();
  mockIPC(command);
  render(<App />);
  expect(
    screen.getByText(
      'Prévia no navegador. Abra o app desktop para conectar ao Rust.',
    ),
  ).toBeInTheDocument();
  expect(command).not.toHaveBeenCalled();
});
