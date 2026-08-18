init:{[]
    system"l ./analytics/markOutImpact.q";
    system"l ./data/generator.q";
    scenario::.synth.buildScenario[];
    impact:: .synth.checkImpactRecovery[scenario;.impact.calc;.impact.decompose];
    markout:: .markout.calc[scenario`trades;scenario`rate];
 };

init[];