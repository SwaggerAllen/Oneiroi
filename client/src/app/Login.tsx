import { useState } from 'react';
import type { GateState } from '../api/client';
import { Button } from '../components/Button';
import { Field } from '../components/Field';

export interface LoginProps {
  onLogin: (email: string, password: string) => void;
  error?: string | null;
  // The front door (gaia#19): closed shows no way to sign up; invite asks
  // for a code; open takes anyone, a code optional.
  door?: GateState | null;
  onSignUp?: (email: string, password: string, code: string | null) => void;
}

const MIN_PASSWORD = 10;

export function Login({ onLogin, error, door = null, onSignUp }: LoginProps) {
  const [mode, setMode] = useState<'in' | 'up'>('in');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [code, setCode] = useState('');
  const signingUp = mode === 'up';
  const canSignUp = door === 'invite' || door === 'open';
  const ready = !signingUp || (password.length >= MIN_PASSWORD && (door !== 'invite' || code.trim() !== ''));
  return (
    <form
      aria-label={signingUp ? 'Create an account' : 'Sign in'}
      onSubmit={(event) => {
        event.preventDefault();
        if (!ready) return;
        if (signingUp) onSignUp?.(email, password, code.trim() || null);
        else onLogin(email, password);
      }}
      style={{
        maxWidth: 360,
        margin: 'var(--space-8) auto',
        padding: 'var(--space-4)',
        display: 'flex',
        flexDirection: 'column',
        gap: 'var(--space-4)',
      }}
    >
      <h1 style={{ margin: 0, fontSize: 28, lineHeight: '34px', fontWeight: 600 }}>Oneiroi</h1>
      <Field label="Email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="username" />
      <Field
        label={signingUp ? `Password (at least ${MIN_PASSWORD} characters)` : 'Password'}
        type="password"
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        autoComplete={signingUp ? 'new-password' : 'current-password'}
      />
      {signingUp ? (
        <Field
          label={door === 'invite' ? 'Invite code' : 'Invite code (optional)'}
          value={code}
          onChange={(e) => setCode(e.target.value)}
          autoComplete="off"
          autoCapitalize="characters"
        />
      ) : null}
      {error ? <p style={{ margin: 0, color: 'var(--danger)', fontSize: 13 }}>{error}</p> : null}
      <Button variant="primary" type="submit" disabled={!ready}>
        {signingUp ? 'Create account' : 'Sign in'}
      </Button>
      {canSignUp ? (
        <Button variant="quiet" type="button" onClick={() => setMode(signingUp ? 'in' : 'up')}>
          {signingUp ? 'I have an account' : door === 'invite' ? 'I have an invite' : 'Create an account'}
        </Button>
      ) : null}
    </form>
  );
}
