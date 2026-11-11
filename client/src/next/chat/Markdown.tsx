import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { useSubject } from '../state/resident';
import { hardBreaks } from './breaks';
import { CITE_SCHEME, linkCitations, parseCite, type Citation } from './cite';
import * as css from './chat.css';

/**
 * Her words, rendered: markdown with no raw HTML (react-markdown's
 * default), and her citations as chips that open a peek.
 */
export function Markdown({ text, onCite, breaks = false }: { text: string; onCite: (c: Citation) => void; breaks?: boolean }) {
  const { slug } = useSubject();
  return (
    <div className={css.prose}>
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        urlTransform={(url) => (url.startsWith(CITE_SCHEME) || /^(https?:|mailto:|#)/.test(url) ? url : '')}
        components={{
          a: ({ href, children }) => {
            const cite = href ? parseCite(href) : null;
            if (cite) {
              return (
                <button type="button" className={css.chip} onClick={() => onCite(cite)}>
                  {children}
                </button>
              );
            }
            return (
              <a href={href} target="_blank" rel="noreferrer noopener">
                {children}
              </a>
            );
          },
        }}
      >
        {linkCitations(breaks ? hardBreaks(text) : text, slug)}
      </ReactMarkdown>
    </div>
  );
}
