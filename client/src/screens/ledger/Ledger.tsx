import { useState } from 'react';
import type { Ledger as LedgerData } from '../../api/types';
import { BudgetLine } from '../../components/BudgetLine';
import { Button } from '../../components/Button';
import { Card } from '../../components/Card';
import { Field } from '../../components/Field';
import { TopBar } from '../../components/TopBar';

export interface LedgerProps {
  ledger: LedgerData;
  onSetBudget?: (purpose: string, cap: string | null, period: string) => void;
  onStoreKey?: (key: string) => void;
}

// Ledger (spec §10): key status; budget lines with spend; spend by
// purpose, by model and by actor. Platform tokens are a later phase.
export function Ledger({ ledger, onSetBudget, onStoreKey }: LedgerProps) {
  const [purpose, setPurpose] = useState(ledger.purposes[0] ?? 'chat');
  const [cap, setCap] = useState('');
  const [period, setPeriod] = useState('month');
  const [key, setKey] = useState('');
  return (
    <div style={{ display: 'flex', flexDirection: 'column', minHeight: '100%' }}>
      <TopBar title="Ledger" line={`Spend since ${ledger.spend.since.slice(0, 10)}`} />
      <main style={{ flex: 1, padding: 'var(--space-4)', display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
        <Card title="Your OpenRouter key">
          <p style={{ margin: 0, fontSize: 15 }}>
            {ledger.key.present ? `Stored since ${ledger.key.stored_at?.slice(0, 10)}.` : 'No key stored; nothing can be asked of a model until one is.'}
          </p>
          {onStoreKey ? (
            <form
              onSubmit={(event) => {
                event.preventDefault();
                if (key.trim()) onStoreKey(key.trim());
                setKey('');
              }}
              style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-end' }}
            >
              <Field label={ledger.key.present ? 'Rotate the key' : 'Paste the key'} type="password" value={key} onChange={(e) => setKey(e.target.value)} />
              <Button variant="primary" type="submit" disabled={key.trim() === ''}>
                {ledger.key.present ? 'Rotate' : 'Store'}
              </Button>
            </form>
          ) : null}
        </Card>
        <Card title="Budget lines">
          {ledger.budgets.length === 0 ? (
            <p style={{ margin: 0, fontSize: 15, color: 'var(--ink-muted)' }}>No lines yet: a purpose with no line has no limit.</p>
          ) : (
            ledger.budgets.map((line) => <BudgetLine key={`${line.purpose}-${line.period}`} line={line} />)
          )}
          {onSetBudget ? (
            <form
              onSubmit={(event) => {
                event.preventDefault();
                onSetBudget(purpose, cap.trim() === '' ? null : cap.trim(), period);
              }}
              style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'flex-end', flexWrap: 'wrap' }}
            >
              <label style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 13 }}>
                <span style={{ fontWeight: 500, color: 'var(--ink-muted)' }}>Purpose</span>
                <select value={purpose} onChange={(e) => setPurpose(e.target.value)} style={{ minHeight: 'var(--control-h)' }}>
                  {ledger.purposes.map((p) => (
                    <option key={p} value={p}>
                      {p}
                    </option>
                  ))}
                </select>
              </label>
              <Field label="Cap in dollars (blank for no limit)" value={cap} onChange={(e) => setCap(e.target.value)} inputMode="decimal" />
              <label style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-1)', fontSize: 13 }}>
                <span style={{ fontWeight: 500, color: 'var(--ink-muted)' }}>Per</span>
                <select value={period} onChange={(e) => setPeriod(e.target.value)} style={{ minHeight: 'var(--control-h)' }}>
                  <option value="day">day</option>
                  <option value="week">week</option>
                  <option value="month">month</option>
                </select>
              </label>
              <Button type="submit">Set the line</Button>
            </form>
          ) : null}
        </Card>
        <SpendTable title="By purpose" rows={ledger.spend.by_purpose} />
        <SpendTable title="By model" rows={ledger.spend.by_model} />
        <SpendTable title="By actor" rows={ledger.spend.by_actor} />
      </main>
    </div>
  );
}

function SpendTable({ title, rows }: { title: string; rows: LedgerData['spend']['by_purpose'] }) {
  return (
    <Card title={title}>
      {rows.length === 0 ? (
        <p style={{ margin: 0, fontSize: 15, color: 'var(--ink-muted)' }}>Nothing spent yet.</p>
      ) : (
        <table style={{ borderCollapse: 'collapse', width: '100%', fontSize: 15 }}>
          <thead>
            <tr style={{ fontSize: 13, color: 'var(--ink-muted)', textAlign: 'left' }}>
              <th style={{ fontWeight: 500, padding: 'var(--space-1) 0' }}>{title.slice(3)}</th>
              <th style={{ fontWeight: 500, padding: 'var(--space-1) 0' }}>calls</th>
              <th style={{ fontWeight: 500, padding: 'var(--space-1) 0', textAlign: 'right' }}>cost</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.key} style={{ borderTop: '1px solid var(--hairline)' }}>
                <td style={{ padding: 'var(--space-2) 0' }}>{row.key}</td>
                <td style={{ padding: 'var(--space-2) 0', fontFamily: 'var(--font-mono)', fontSize: 13 }}>{row.calls}</td>
                <td style={{ padding: 'var(--space-2) 0', fontFamily: 'var(--font-mono)', fontSize: 13, textAlign: 'right' }}>${row.cost}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </Card>
  );
}
