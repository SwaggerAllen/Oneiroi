import type { RegressionCard } from '../../api/types';

function trialLabel(card: RegressionCard) {
  if (card.test_number !== null) return `Test #${card.test_number}`;
  if (card.behaviour_number !== null) return `From habit #${card.behaviour_number}`;
  return `From promise #${card.commitment_number}`;
}

// The deck in the server's order, by trial and then by card ref, which
// says nothing of the model; cards pushed live are put in the same place.
export function byTrial(cards: RegressionCard[]) {
  const groups = new Map<string, { key: string; label: string; cards: RegressionCard[] }>();
  for (const card of sortCards(cards)) {
    const key = `${card.test_number}-${card.behaviour_number}-${card.commitment_number}`;
    const group = groups.get(key) ?? { key, label: trialLabel(card), cards: [] };
    group.cards.push(card);
    groups.set(key, group);
  }
  return [...groups.values()];
}

export function sortCards(cards: RegressionCard[]) {
  const n = (x: number | null) => (x === null ? Number.MAX_SAFE_INTEGER : x);
  return [...cards].sort(
    (a, b) =>
      n(a.test_number) - n(b.test_number) ||
      n(a.behaviour_number) - n(b.behaviour_number) ||
      n(a.commitment_number) - n(b.commitment_number) ||
      (a.card_ref < b.card_ref ? -1 : a.card_ref > b.card_ref ? 1 : 0),
  );
}
