import '@testing-library/jest-dom/vitest';
import { afterEach, vi } from 'vitest';
import { cleanup } from '@testing-library/react';
import { clearMocks } from '@tauri-apps/api/mocks';

afterEach(() => {
  cleanup();
  clearMocks();
  vi.unstubAllGlobals();
});
