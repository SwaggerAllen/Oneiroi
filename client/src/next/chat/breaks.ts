/**
 * Every single line break kept as a break, outside code fences: markdown
 * otherwise joins a pasted conversation's lines into one paragraph, and
 * who said what is the whole point of one. The file is left as written;
 * this changes only how it is shown.
 */
export function hardBreaks(text: string): string {
  return text
    .split(/(^```[^\n]*\n[\s\S]*?^```[^\n]*$)/m)
    .map((part, i) => (i % 2 === 1 ? part : part.replace(/([^\n])\n(?=[^\n])/g, '$1  \n')))
    .join('');
}
