import type { ReactNode } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Button, Menu, MenuItem, MenuTrigger, Popover } from 'react-aria-components';
import { api } from '../../api/client';
import * as css from './reacts.css';

export type React = { turn_ref: string | null; emoji: string; by: 'witness' | 'resident' };

/**
 * The reacts on one message, and on hers the menu to add his: each emoji
 * with its meaning beside it, from the vocabulary the two of them keep
 * (REACTIONS.md). A react wakes nobody.
 */
export function Reacts({
  residentId,
  sessionKey,
  turnRef,
  reacts,
  canReact,
  residentName,
  extra,
}: {
  residentId: string;
  sessionKey: string;
  turnRef: string;
  reacts: React[];
  canReact: boolean;
  residentName: string;
  /** More of the message's own actions, beside the react button. */
  extra?: ReactNode;
}) {
  const queries = useQueryClient();
  const vocabulary = useQuery({
    queryKey: ['resident', residentId, 'soul', 'reacts-vocabulary'],
    queryFn: () => api.reactVocabulary(residentId),
    enabled: canReact,
    staleTime: 10 * 60_000,
  });
  const add = useMutation({
    mutationFn: (emoji: string) => api.react(residentId, { kind: 'message', session_key: sessionKey, turn_ref: turnRef }, emoji),
    onSuccess: () => queries.invalidateQueries({ queryKey: ['resident', residentId, 'chat', 'reacts', sessionKey] }),
  });
  const meaning = new Map((vocabulary.data ?? []).map((v) => [v.emoji, v.meaning]));

  return (
    <div className={css.row}>
      {reacts.map((r, i) => (
        <span key={`${r.emoji}-${i}`} className={r.by === 'witness' ? css.mine : css.hers} title={meaning.get(r.emoji)}>
          {r.emoji} {r.by === 'witness' ? 'you' : residentName}
          {meaning.get(r.emoji) ? ` · ${meaning.get(r.emoji)}` : ''}
        </span>
      ))}
      {canReact && (
        <MenuTrigger>
          <Button className={css.add} aria-label="React">
            React
          </Button>
          <Popover className={css.popover} placement="top start">
            <Menu className={css.menu} aria-label="Reacts" onAction={(emoji) => add.mutate(String(emoji))}>
              {(vocabulary.data ?? []).map((v) => (
                <MenuItem key={v.emoji} id={v.emoji} className={css.item} textValue={v.meaning}>
                  <span className={css.emoji}>{v.emoji}</span>
                  <span>{v.meaning}</span>
                </MenuItem>
              ))}
            </Menu>
          </Popover>
        </MenuTrigger>
      )}
      {extra}
    </div>
  );
}
