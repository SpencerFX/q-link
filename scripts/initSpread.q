init:{[]
    system"l ./analytics/spread.q";
    system"l ./data/spreadGenerator.q";
    scenario::.spreadSynth.genSession[.z.p-0D02:00:00;3000;1.5];
    recovery::.spreadSynth.checkRecovery scenario;
    byRegime::.spread.byRegime[scenario`quotes;`$()];
    byTime::.spread.byTime[scenario`quotes;`minute;`$()];
 };

init[];