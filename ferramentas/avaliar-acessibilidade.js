// Avaliação com o QualWeb (o motor do AccessMonitor): regras ACT + técnicas WCAG 2.1, níveis A e AA.
const { QualWeb } = require('@qualweb/core');
const { ACTRules } = require('@qualweb/act-rules');
const { WCAGTechniques } = require('@qualweb/wcag-techniques');
const fs = require('fs');

const BASE = 'http://localhost:8765/index.html';
const ROTAS = (process.argv[2] || '#e1,#e1-desporto,#e1-ler,#acessibilidade,#cartas,#concurso,#agenda,#redacao,#painel').split(',');

(async () => {
  const qw = new QualWeb();
  qw.use({ async afterPageLoad(page) { await new Promise(r => setTimeout(r, 3500)); } });
  await qw.start({ maxConcurrency: 1, timeout: 90000 }, { headless: true, executablePath: '/usr/bin/google-chrome' });
  const out = {};
  for (const r of ROTAS) {
    const url = BASE + r;
    const rep = await qw.evaluate({
      url,
      viewport: { mobile: true, landscape: false, width: 390, height: 844 },
      modules: [new ACTRules({ levels: ['A', 'AA'] }), new WCAGTechniques({ levels: ['A', 'AA'] })],
    });
    const R = rep[url];
    const res = [];
    for (const mod of ['act-rules', 'wcag-techniques']) {
      const m = R.modules[mod]; if (!m) continue;
      for (const [code, a] of Object.entries(m.assertions)) {
        if (a.metadata.outcome === 'failed' || a.metadata.outcome === 'warning') {
          const crit = (a.metadata['success-criteria'] || []).map(c => c.name + ' (' + c.level + ')').join(', ');
          const ex = a.results.filter(x => x.verdict === a.metadata.outcome).slice(0, 4).map(x => (x.elements || []).map(e => e.pointer || e.htmlCode).join(' ').slice(0, 160) + ' :: ' + (x.description || '').slice(0, 140));
          res.push({ mod, code, nome: a.name, outcome: a.metadata.outcome, crit, n: a.metadata[a.metadata.outcome], ex });
        }
      }
    }
    out[r] = { passed: ['act-rules', 'wcag-techniques'].reduce((s, k) => s + (R.modules[k] ? R.modules[k].metadata.passed : 0), 0), failed: res.filter(x => x.outcome === 'failed'), warnings: res.filter(x => x.outcome === 'warning') };
    console.log(`${r}: ${out[r].passed} passaram · ${out[r].failed.length} regras com erros · ${out[r].warnings.length} com avisos`);
  }
  fs.writeFileSync('/home/claude/qw/relatorio.json', JSON.stringify(out, null, 1));
  await qw.stop();
})().catch(e => { console.error(e); process.exit(1); });
