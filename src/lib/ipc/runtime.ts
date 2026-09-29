import { invoke } from '@tauri-apps/api/core';

export interface RuntimeInfo {
  appName: string;
  appVersion: string;
  platform: string;
  architecture: string;
  ipcVersion: number;
}

export function getRuntimeInfo(): Promise<RuntimeInfo> {
  return invoke<RuntimeInfo>('runtime_info');
}
