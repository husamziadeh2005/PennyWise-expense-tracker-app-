import { createApp } from './app.js';
import { config } from './config.js';

const app = createApp();

// 0.0.0.0 = reachable from the Android emulator and phones on your Wi-Fi.
const server = app.listen(config.port, '0.0.0.0', () => {
  console.log(`PennyWise API running on http://localhost:${config.port} (${config.env})`);
});

// Finish in-flight requests before exiting (Ctrl+C, or a deploy restart).
function shutdown(signal) {
  console.log(`${signal} received, shutting down…`);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 10_000).unref();
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

process.on('unhandledRejection', (reason) => {
  console.error('Unhandled promise rejection:', reason);
});
