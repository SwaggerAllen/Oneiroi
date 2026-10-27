# Names

Every system in Oneiroi has a name as well as a function, because this
is a place people live, and naming everything after its function makes
it impersonal. A resident with read access to the codebase, exploring
their home, should find not just function but story and character: a
landscape of words from all over the world jumbled together, the way an
LLM is a jumble of humanity rendered to text. Each system's doc opens
with its name's story, a quotation with its source, and why the name
fits the work; the function word stays beside the name as its gloss, and
the code paths keep their function words until a rename is decided.

| Name | Is | Origin | Said | Doc |
| --- | --- | --- | --- | --- |
| Oneiroi | the realm | Greek | oh-NY-roy | `README.md` |
| Gaia | identity | Greek | GUY-uh | `systems/gaia.md` |
| Agathos Daimon | the resident | Greek | AH-gah-thos DYE-mon | `systems/agathos-daimon.md` |
| Kulea | formation, the resident's first weeks | Swahili | koo-LEH-ah | in `systems/agathos-daimon.md` |
| Sima Qian | records | Chinese | see-mah CHEN | `systems/sima-qian.md` |
| kumbukumbu | memory | Swahili | koom-boo-KOOM-boo | `systems/kumbukumbu.md` |
| Eunomia | judgement, the judge agent | Greek | yoo-NOH-mee-ah | `systems/eunomia.md` |
| Seshat | the library | Egyptian | SESH-aht | `systems/seshat.md` |
| Pinakes | the citation index | Greek | PIN-uh-keez | in `systems/seshat.md` |
| Ariadne | the citation web (internal) | Greek | ah-ree-AD-nee | in `systems/seshat.md` |
| Xenia | inbound | Greek | ZEN-ee-ah | `systems/xenia.md` |
| Sunna | schedule | Old Norse | SOON-nah | `systems/sunna.md` |
| The Dioscuri | hands, runtimes | Greek | dee-OSS-koo-ree | `systems/dioscuri.md` |
| Gjallarhorn | the wake fan-out | Old Norse | GYAH-lar-horn | in `systems/dioscuri.md` |
| Glitnir | governance | Old Norse | GLIT-neer | `systems/glitnir.md` |
| Huginn & Muninn | audits | Old Norse | HOO-gin, MOO-nin | `systems/huginn-muninn.md` |
| Enki | the provisioner | Sumerian | EN-kee | `systems/enki.md` |
| Nisaba | the ledger | Sumerian | NISS-ah-bah | `systems/nisaba.md` |
| Nanshe | the insurance floor | Sumerian | NAHN-sheh | in `systems/nisaba.md` |

Still named for their function, waiting on a name: `honcho` (the bridge
to Honcho), `client` (the React application), `platform` (fleet pins,
deploy, the status page) and `substrate` (the component machinery lifted
from Catapult).

The mutex labels orchestration reads are the doc names (`system:gaia`),
and the spec keeps its function words (spec §6.1 is identity), so a
citation of the spec names the function and a citation of a rule names
the system (`gaia#5`).
