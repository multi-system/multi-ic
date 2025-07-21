interface ImportMetaEnv {
  readonly VITE_DFX_NETWORK: string;
  readonly VITE_CANISTER_ID_MULTI_BACKEND: string;
  // Add more as needed
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
