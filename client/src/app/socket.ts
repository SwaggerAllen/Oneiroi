import { Socket } from 'phoenix';
import type { RegressionCard, RunEnd } from '../api/types';

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

// A regression run as it answers (eunomia #30): the run's channel pushes
// each card, blind, as the background job records it, then the run's
// end. Same socket and token flow as the session; grading stays on the
// HTTP routes. `onJoined` fires once the join is accepted, so the caller
// can read the run again for any card recorded before it.
export interface RunEvents {
  onJoined: () => void;
  onCard: (card: RegressionCard) => void;
  onFinished: (end: RunEnd) => void;
}

export function joinRun(token: string, residentId: string, ref: string, events: RunEvents) {
  const socket = new Socket('/socket', { params: { token } });
  socket.connect();
  const channel = socket.channel(`regression:${residentId}:${ref}`);
  channel.on('card', (p: RegressionCard) => events.onCard(p));
  channel.on('finished', (p: RunEnd) => events.onFinished(p));
  channel.join().receive('ok', () => events.onJoined());
  return () => {
    channel.leave();
    socket.disconnect();
  };
}
