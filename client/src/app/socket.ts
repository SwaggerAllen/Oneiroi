import { Socket } from 'phoenix';

// The streamed conversation (spec §5): the session channel delivers
// deltas and the turn as it lands. The socket takes a five-minute token
// from /v1/me/socket-token (brain #6), never the cookie.
export interface ChannelEvents {
  onStarted: (turnRef: string) => void;
  onDelta: (turnRef: string, text: string) => void;
  onTurn: (turnRef: string) => void;
  onFailed: (turnRef: string, reason: string) => void;
}

export function joinSession(token: string, residentId: string, key: string, events: ChannelEvents) {
  const socket = new Socket('/socket', { params: { token } });
  socket.connect();
  const channel = socket.channel(`session:${residentId}:${key}`);
  channel.on('turn_started', (p: { turn_ref: string }) => events.onStarted(p.turn_ref));
  channel.on('delta', (p: { turn_ref: string; text: string }) => events.onDelta(p.turn_ref, p.text));
  channel.on('turn', (p: { turn_ref: string }) => events.onTurn(p.turn_ref));
  channel.on('failed', (p: { turn_ref: string; reason: string }) => events.onFailed(p.turn_ref, p.reason));
  channel.join();
  return () => {
    channel.leave();
    socket.disconnect();
  };
}
