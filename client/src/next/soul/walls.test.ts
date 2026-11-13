import { describe, expect, it } from 'vitest';
import { personOf, sameWall, wallsOf, wallWords, whoOf, withWalls } from './walls';

const persons = { witness: 'account:a', resident: 'resident:r' };
const wall = { memory: { person: 'account:a', domain: 'recovery' }, context: { person: 'account:a', domain: 'business' } };

describe('the domain walls (agathos-daimon#45)', () => {
  it('says a wall in words', () => {
    expect(wallWords(wall, persons, 'Lily')).toBe('your recovery is never named into your business');
    expect(wallWords({ ...wall, context: { person: '*', domain: '*' } }, persons, 'Lily')).toBe('your recovery is never named into any other context');
    expect(wallWords({ memory: { person: 'resident:r', domain: 'free-time' }, context: { person: 'account:a', domain: '*' } }, persons, 'Lily')).toBe("Lily's free-time is never named into anything of yours");
  });

  it('reads who a person is and writes them back', () => {
    expect(whoOf('account:a', persons)).toBe('witness');
    expect(whoOf('*', persons)).toBe('anyone');
    expect(whoOf('account:z', persons)).toBe('other');
    expect(personOf('resident', persons)).toBe('resident:r');
    expect(personOf('anyone', persons)).toBe('*');
  });

  it('keeps the switches with the walls, and drops the key with none', () => {
    expect(withWalls({ trials: true }, [wall])).toEqual({ trials: true, domain_walls: [wall] });
    expect(withWalls({ trials: true }, [])).toEqual({ trials: true });
    expect(wallsOf({ trials: true, domain_walls: [wall] })).toEqual([wall]);
    expect(wallsOf(undefined)).toEqual([]);
    expect(sameWall(wall, { ...wall })).toBe(true);
  });
});
