import { useState } from 'react';
import { Button } from '../components/Button';
import { Field } from '../components/Field';

export function Login({ onLogin, error }: { onLogin: (email: string, password: string) => void; error?: string | null }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        onLogin(email, password);
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
      <Field label="Password" type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" />
      {error ? <p style={{ margin: 0, color: 'var(--danger)', fontSize: 13 }}>{error}</p> : null}
      <Button variant="primary" type="submit">
        Sign in
      </Button>
    </form>
  );
}
