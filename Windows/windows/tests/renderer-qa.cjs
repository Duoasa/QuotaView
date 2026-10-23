// Runs in isolated smoke windows with fixture data, never in a normal session.
const fs = require("node:fs");
const path = require("node:path");
module.exports = async function verifyUI({
  island,
  capsule,
  preferences,
  folder,
}) {
  const now = Date.now();
  const days = Array.from({ length: 294 }, (_, index) => {
    const date = new Date(now);
    date.setDate(date.getDate() - 293 + index);
    return {
      date: date.toISOString().slice(0, 10),
      total: 100000 + index * 711,
      cost: 0.8 + (index % 13) * 0.4,
    };
  });
  const fixture = {
    locale: "zh",
    settings: {
      language: "zh",
      theme: "dark",
      material: "glass", // Legacy saved preferences must still render solid.
      blackRatio: 0.2,
      islandWidth: 680,
      autoExpand: false,
    },
    tasks: [
      {
        id: "qa-think",
        provider: "codex",
        title: "规划下一次产品迭代",
        status: "thinking",
        model: "6 Astra · High",
        publicText: "梳理目标，分析实现方案",
        tokens: { total: 24800 },
        startedAt: now - 60000,
      },
      {
        id: "qa-work",
        provider: "codex",
        title: "构建 QuotaView Windows",
        status: "working",
        model: "6 Sol · High",
        publicText: "编译应用，验证构建结果",
        tokens: { total: 128000 },
        progress: { completed: 3, total: 5 },
        startedAt: now - 120000,
      },
    ],
    quotas: {
      codex: {
        updatedAt: now,
        account: { plan: "Plus" },
        credits: { balance: 25 },
        windows: [
          { windowMinutes: 300, usedPercent: 28, resetAt: now + 10800000 },
          { windowMinutes: 10080, usedPercent: 36, resetAt: now + 600000000 },
        ],
      },
    },
    usage: {
      codex: { days, localDays: days, summary: { lifetimeTokens: 2100000000 } },
    },
    providers: { codex: { connected: true, enabled: true } },
    ui: { expanded: false, pinned: false },
  };
  const run = (win, code) =>
    win.webContents.executeJavaScript(
      `(async()=>{const wait=ms=>new Promise(r=>setTimeout(r,ms));const check=(v,m)=>{if(!v)throw Error(m);};${code}})()`,
    );
  const inject = async (win, value) =>
    run(
      win,
      `window.QVUITest.setSnapshot(${JSON.stringify(value)});await wait(150);return true;`,
    );
  const capture = async (win, name) => {
    if (!win.capture || !folder) return null;
    const target = path.join(folder, name);
    fs.mkdirSync(target, { recursive: true });
    return win.capture(target);
  };
  await inject(island, fixture);
  const frames = [];
  const setBounds = island.setBounds.bind(island);
  island.setBounds = (b, animate) => {
    frames.push({ ...b });
    setBounds(b, animate);
  };
  const hover = await run(
    island,
    `
    const main=document.querySelector('.island-window');
    const enter=()=>main.dispatchEvent(new MouseEvent('mouseover',{bubbles:true,relatedTarget:document.body}));
    const leave=()=>main.dispatchEvent(new MouseEvent('mouseout',{bubbles:true,relatedTarget:document.body}));
    enter();await wait(80);check(main.classList.contains('collapsed'),'Hover opened before dwell');
    await wait(220);check(main.classList.contains('expanded'),'Hover did not expand with automatic popups disabled');
    document.querySelector('[aria-label="固定展开"]').click();leave();await wait(550);
    check(main.classList.contains('expanded'),'Pinned island collapsed');
    enter();document.querySelector('[aria-label="取消固定"]').click();leave();await wait(550);
    check(main.classList.contains('collapsed'),'Pointer exit did not collapse');
    enter();await wait(250);main.dispatchEvent(new KeyboardEvent('keydown',{key:'Escape',bubbles:true}));await wait(200);
    check(main.classList.contains('collapsed'),'Escape did not collapse');
    enter();await wait(250);check(main.classList.contains('collapsed'),'Collapsed island reopened before pointer exit');
    leave();enter();await wait(250);check(main.classList.contains('expanded'),'Hover did not rearm after exit');
    return {dwell:true,pinned:true,leave:true,escape:true,reentry:true};
  `,
  );
  island.setBounds = setBounds;
  if (frames.length > 12) throw Error("Expansion sends per-frame native IPC");
  await run(island, "await wait(350);return true;");
  const motionEvidence = await capture(island, "native-motion");
  if (
    motionEvidence?.motion &&
    (motionEvidence.motion.viewportResizes > 1 ||
      motionEvidence.motion.frames < 3)
  )
    throw Error("Native animation must keep the WebView viewport fixed");
  await inject(island, {
    ...fixture,
    ui: { expanded: true, pinned: false },
    tasks: [
      {
        ...fixture.tasks[1],
        id: "qa-wait",
        status: "waiting",
        title: "发布前的最终检查",
        progress: { completed: 1, total: 3 },
      },
      ...fixture.tasks,
    ],
  });
  await run(
    island,
    `document.querySelector('.island-window').dispatchEvent(new MouseEvent('mouseout',{bubbles:true,relatedTarget:document.body}));await wait(550);check(document.querySelector('.island-window.expanded'),'Pending request was collapsed');return true;`,
  );
  await capture(island, "tasks");
  const attentionFixture = {
    ...fixture,
    settings: { ...fixture.settings, autoExpand: true },
    ui: { expanded: false, pinned: false },
    tasks: [
      {
        ...fixture.tasks[1],
        id: "qa-async-approval",
        status: "working",
        tool: "wait",
        approval: {
          id: "question-1",
          kind: "question",
          asynchronous: true,
          canRespond: false,
          title: "选择模拟测试方案",
          questions: [
            {
              id: "test",
              question: "选择模拟测试方案",
              options: [{ label: "快速检查" }, { label: "完整检查" }],
            },
          ],
        },
      },
      fixture.tasks[0],
    ],
  };
  await inject(island, attentionFixture);
  const attention = await run(
    island,
    `
    await wait(450);
    const card=document.querySelector('[data-task-id="qa-async-approval"]');
    check(document.querySelector('.island-window.expanded'),'Pending async question did not expand');
    check(card.classList.contains('status-waiting')&&card.querySelector('.task-status').textContent==='待确认','Card status disagrees with pending count');
    check(card.querySelector('.activity-text').textContent==='等待你的回答','Pending card still shows wait tool');
    check(card.dataset.focused==='true'&&card.getAttribute('aria-expanded')==='true','Pending task was not selected and focused');
    check(document.querySelector('.approval-panel')?.textContent.includes('选择模拟测试方案'),'Approval panel did not open automatically');
    check(document.querySelector('.header-status').textContent.includes('1'),'Pending badge disagrees');
    check(document.querySelector('.task-detail.status-waiting'),'Detail status disagrees');
    check(window.QVEffects.displayState({status:'working',approval:{id:'q',kind:'question'}})==='waiting','GPU effect state disagrees');
    document.querySelector('[aria-label="收起"]').click();await wait(250);
    return {asyncQuestion:true,cardState:true,details:true,focus:true};
  `,
  );
  await inject(island, attentionFixture);
  await run(
    island,
    "check(document.querySelector('.island-window.collapsed'),'Same pending request reopened after manual collapse');return true;",
  );
  const nextAttention = {
    ...attentionFixture,
    tasks: [
      {
        ...attentionFixture.tasks[0],
        approval: { ...attentionFixture.tasks[0].approval, id: "question-2" },
      },
      fixture.tasks[0],
    ],
  };
  await inject(island, nextAttention);
  await run(
    island,
    "await wait(350);check(document.querySelector('.island-window.expanded .approval-panel'),'New request did not reopen detail');return true;",
  );
  await capture(island, "approval-auto-open");
  await inject(island, {
    ...nextAttention,
    tasks: [
      { ...attentionFixture.tasks[0], approval: undefined },
      fixture.tasks[0],
    ],
  });
  await run(
    island,
    `check(document.querySelector('[data-task-id="qa-async-approval"]').classList.contains('status-working'),'Settled request stayed yellow');check(!document.querySelector('.approval-panel'),'Settled approval panel remains');check(!document.querySelector('.header-status.warning'),'Settled count remains');return true;`,
  );
  await inject(island, { ...fixture, ui: { expanded: true, pinned: false }, tasks: [{...fixture.tasks[1],id:"qa-wait",status:"waiting",title:"发布前的最终检查"},...fixture.tasks] });
  const motion = await run(
    island,
    `
    const canvases=[...document.querySelectorAll('.qv-orb-canvas,.qv-quantum-canvas')];
    const before=canvases.map(c=>c.toDataURL()),frames=window.QVEffects.diagnostics().frames;
    await wait(450);
    check(window.QVEffects.diagnostics().frames>frames+2,'Task effect scheduler stalled');
    check(canvases.some((c,i)=>c.classList.contains('qv-orb-canvas')&&c.toDataURL()!==before[i]),'Task orb is static');
    check(canvases.some((c,i)=>c.classList.contains('qv-quantum-canvas')&&c.toDataURL()!==before[i]),'Task quantum field is static');
    return window.QVEffects.diagnostics();
  `,
  );

  const focus = await run(
    island,
    `
    const cards=()=>[...document.querySelectorAll('.task-list .task-card')];
    const assertFocus=id=>{
      const all=cards(), focused=all.filter(c=>c.dataset.focused==='true');
      check(focused.length===1&&focused[0].dataset.taskId===id,'Incorrect focused card: '+id);
      check(all.reduce((n,c)=>n+c.querySelectorAll('.qv-quantum-canvas').length,0)===1,'Multiple quantum task cards');
      for(const c of all){
        check(!!c.querySelector('.qv-quantum-canvas')===(c.dataset.taskId===id),'Quantum effect assigned by status');
        check(!!c.querySelector('.qv-orb-canvas')===(c.dataset.taskId!==id),'Nonfocused card missing orb');
      }
    };
    assertFocus('qa-wait');
    cards().find(c=>c.dataset.taskId==='qa-think').click();await wait(180);
    assertFocus('qa-think');
    const canvas=cards().find(c=>c.dataset.taskId==='qa-think').querySelector('canvas');
    const before=canvas.toDataURL();await wait(450);
    check(before!==canvas.toDataURL(),'Focused thinking quantum effect is static');
    cards().find(c=>c.dataset.taskId==='qa-think').click();await wait(80);
    assertFocus('qa-think');
    check(!document.querySelector('.task-list .task-detail'),'Closing detail lost separation from focus');
    cards().find(c=>c.dataset.taskId==='qa-work').dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}));
    await wait(180);assertFocus('qa-work');
    cards().find(c=>c.dataset.taskId==='qa-work').click();await wait(80);
    assertFocus('qa-work');
    return {exclusive:true,thinkingAnimated:true,keyboard:true,retainedAfterDetailClose:true};
  `,
  );
  // Removing the focused task must hand focus to the first remaining card.
  await inject(island, {
    ...fixture,
    tasks: [fixture.tasks[0]],
    ui: { expanded: true },
  });
  await run(
    island,
    "const c=document.querySelector('.task-list .task-card');check(c?.dataset.taskId==='qa-think'&&c.dataset.focused==='true'&&c.querySelector('.qv-quantum-canvas'),'Removed focus was not reassigned');return true;",
  );
  focus.removalFallback = true;
  await inject(island, { ...fixture, ui: { expanded: true } });
  const solid = await run(
    island,
    `
    const shell=getComputedStyle(document.querySelector('.island-shell'));
    check(shell.backgroundColor==='rgb(0, 0, 0)'&&shell.backdropFilter==='none','Island still uses glass');
    await window.quotaView.updateSettings({material:'glass',blackRatio:0.2});
    const snapshot=await window.quotaView.snapshot();
    check(snapshot.settings.material==='solid'&&!('blackRatio' in snapshot.settings),'Legacy material accepted by settings bridge');
    return {island:true,legacySettings:true};
  `,
  );
  if (capsule) {
    await inject(capsule, fixture);
    solid.capsule = await run(
      capsule,
      `
      const el=document.querySelector('.quota-capsule'),style=getComputedStyle(el);
      check(style.backgroundColor==='rgb(27, 27, 32)'&&style.backdropFilter==='none'&&style.opacity==='1','Capsule still uses glass');
      el.classList.add('stale');check(getComputedStyle(el).opacity==='1','Stale capsule became transparent');
      el.classList.remove('stale');return true;
    `,
    );
    const evidence = await capture(capsule, "capsule-solid");
    if (evidence && evidence.material !== "none")
      throw Error("Capsule native backdrop is still enabled");
  }
  for (const win of [island, preferences])
    if (win.qvMaterial !== "none")
      throw Error("Native backdrop is still enabled");

  const usage = await run(
    island,
    `
    document.querySelector('.island-header .quota-capsule').click();await wait(500);
    check(document.querySelectorAll('.quota-card').length===2,'Quota layout');
    check(document.querySelectorAll('.usage-summary-stat').length===3,'Token metrics layout');
    const account=document.querySelector('.account-bento').getBoundingClientRect(),metrics=document.querySelector('.usage-bento-metrics').getBoundingClientRect();
    check(account.left>=metrics.right && Math.abs(account.top-metrics.top)<2,'Account is not beside the quota/token cards');
    const ticket=document.querySelector('.recharge-ticket');check(ticket&&ticket.getAttribute('aria-disabled')==='true'&&ticket.tabIndex===-1,'Recharge card must be noninteractive');
    ticket.click();check(document.querySelector('.usage-dashboard'),'Recharge card navigated');
    document.querySelectorAll('.activity-mode button')[1].click();await wait(70);check(document.querySelectorAll('.activity-cell').length===371,'Weekly aggregation');
    document.querySelectorAll('.activity-mode button')[2].click();await wait(70);check(document.querySelectorAll('.activity-cell').length===371,'Cumulative activity');
    document.querySelectorAll('.activity-mode button')[0].click();await wait(80);
    check(document.querySelector('.usage-panel').scrollWidth<=document.querySelector('.usage-panel').clientWidth+1,'Usage overflow');
    return {bento:true,ticketDisplayOnly:true,activityModes:true};
  `,
  );
  await capture(island, "usage");

  const claudeLayout = await run(
    island,
    `
    const tabs=[...document.querySelectorAll('.usage-provider-tabs button')];
    tabs.find(el=>el.textContent.includes('Claude')).click();await wait(650);
    const shell=document.querySelector('.island-shell').getBoundingClientRect();
    const footer=document.querySelector('.island-footer').getBoundingClientRect();
    const body=document.querySelector('.island-body');
    check(footer.bottom<=innerHeight+1,'Claude footer extends below viewport');
    body.scrollTop=body.scrollHeight;await wait(80);
    const note=document.querySelector('.usage-dashboard > .chart-note').getBoundingClientRect();
    check(note.bottom<=body.getBoundingClientRect().bottom+1,'Claude source note is not reachable');
    return {shellBottom:shell.bottom,footerBottom:footer.bottom,dpi:devicePixelRatio,viewport:innerHeight,scrollable:body.scrollHeight>body.clientHeight};
  `,
  );
  const claudeNative = await capture(island, "usage-claude");
  if (claudeNative?.clipBounds) {
    const clipBottom =
      claudeNative.clipBounds.y + claudeNative.clipBounds.height;
    const contentBottom = claudeLayout.shellBottom * claudeLayout.dpi;
    if (clipBottom + 2 < contentBottom)
      throw Error(
        "Claude content clipped by stale native region: " +
          JSON.stringify({ clipBottom, contentBottom, ...claudeLayout }),
      );
    claudeLayout.nativeRegion = true;
  }
  await run(
    island,
    "document.querySelectorAll('.usage-provider-tabs button')[0].click();await wait(450);return true;",
  );

  await run(
    island,
    "document.querySelectorAll(\'.activity-mode button\')[1].click();await wait(50);return true;",
  );
  await capture(island, "activity-weekly");
  await run(
    island,
    "document.querySelectorAll(\'.activity-mode button\')[2].click();await wait(50);return true;",
  );
  await capture(island, "activity-cumulative");
  await run(
    island,
    "document.querySelectorAll(\'.activity-mode button\')[0].click();return true;",
  );
  await inject(island, {
    ...fixture,
    quotas: {
      codex: {
        ...fixture.quotas.codex,
        windows: [fixture.quotas.codex.windows[1]],
      },
    },
    ui: { expanded: true },
  });
  await run(
    island,
    "await wait(400);const grid=document.querySelector(\'.quota-grid\').getBoundingClientRect(),card=document.querySelector(\'.quota-card\').getBoundingClientRect();check(Math.abs(grid.width-card.width)<2,\'Single quota leaves an empty column\');return true;",
  );
  await capture(island, "usage-single");
  await run(
    island,
    "await window.quotaView.updateSettings({islandWidth:520});await wait(500);const el=document.querySelector('.usage-panel');check(el.scrollWidth<=el.clientWidth+1,'Narrow usage overflow');return true;",
  );
  await capture(island, "usage-narrow");
  await run(
    island,
    "await window.quotaView.updateSettings({islandWidth:680});return true;",
  );
  await inject(preferences, fixture);
  const settings = await run(
    preferences,
    `
    document.querySelector('[data-page="island"]').click();await wait(180);
    const text=document.querySelector('.settings-content').textContent;
    check(!text.includes('空闲')&&!text.includes('任务特效')&&!document.querySelector('.effect-choices'),'Removed preferences remain visible');
    const controls=[...document.querySelectorAll('.window-controls button')].map(el=>{const r=el.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height};});
    check(controls.length===3&&controls.every(r=>Math.abs(r.width-46)<1&&Math.abs(r.height-32)<1),'Caption control sizes');
    check(controls[2].x+controls[2].width<=innerWidth&&controls[0].y<3,'Caption controls are misplaced');
    check(!document.querySelector('.preview-tag'),'Preview annotation remains');
    check(!text.includes('玻璃')&&!text.includes('材质')&&!document.querySelector('#glass-ratio'),'Glass settings remain');
    const shellStyle=getComputedStyle(document.querySelector('.preview-shell')), capsuleStyle=getComputedStyle(document.querySelector('.preview-capsule .quota-capsule'));
    check(shellStyle.backgroundColor==='rgb(0, 0, 0)'&&shellStyle.backdropFilter==='none','Preview island uses glass');
    check(capsuleStyle.backgroundColor==='rgb(27, 27, 32)'&&capsuleStyle.backdropFilter==='none','Preview capsule uses glass');
    check(document.querySelector('.preview-shell .task-card .qv-quantum-canvas')&&!document.querySelector('.preview-shell .task-card .qv-orb-canvas'),'Preview focused effect mismatch');
    const preview=document.querySelector('.island-preview').getBoundingClientRect(), shell=document.querySelector('.preview-shell').getBoundingClientRect();
    check(Math.abs(preview.top-shell.top)<1,'Preview is detached from top');
    const detail=document.querySelector('.settings-detail');check(detail.scrollWidth<=detail.clientWidth+1,'Settings horizontal overflow');
    return {removedPreferences:true,controls,viewport:{width:innerWidth,height:innerHeight,dpi:devicePixelRatio}};
  `,
  );
  await capture(preferences, "settings-island");
  await run(
    preferences,
    `document.querySelector('[data-page="usage"]').click();await wait(100);check(document.querySelectorAll('.settings-content [role="switch"]').length===2,'Usage must expose only two optional modules');return true;`,
  );
  await capture(preferences, "settings-usage");
  // Visit every settings page to catch render errors and horizontal clipping.
  await run(
    preferences,
    `for(const page of ['general','connections','proxy','feedback','about']){document.querySelector('[data-page="'+page+'"]').click();await wait(100);check(!document.querySelector('.fatal-error'),'Settings render failure: '+page);const el=document.querySelector('.settings-detail');check(el.scrollWidth<=el.clientWidth+1,'Settings overflow: '+page);}return true;`,
  );
  preferences.setBounds({
    ...preferences.getBounds(),
    width: 720,
    height: 520,
  });
  await run(
    preferences,
    "await wait(200);for(const page of ['island','connections','proxy','general','usage']){document.querySelector('[data-page=\"'+page+'\"]').click();await wait(100);const el=document.querySelector('.settings-detail');check(el.scrollWidth<=el.clientWidth+1,'Narrow settings overflow: '+page);}return true;",
  );
  await capture(preferences, "settings-narrow");
  const displays = require("electron").screen.getAllDisplays();
  const target = displays.find((d) => d.bounds.x < 0) || displays[0];
  preferences.setBounds({
    ...target.bounds,
    x: target.bounds.x + 30,
    y: target.bounds.y + 30,
    width: 720,
    height: 520,
  });
  preferences.maximize();
  await run(
    preferences,
    "await wait(150);check(document.documentElement.classList.contains('window-maximized'),'Native maximize did not reach titlebar');return true;",
  );
  const maximized = await capture(preferences, "settings-maximized");
  if (maximized) {
    const b = maximized.bounds,
      a = maximized.workArea;
    if (
      b.x < a.x - 2 ||
      b.y < a.y - 2 ||
      b.x + b.width > a.x + a.width + 2 ||
      b.y + b.height > a.y + a.height + 2
    )
      throw Error(
        "Maximized settings escaped display work area: " +
          JSON.stringify(maximized),
      );
  }
  preferences.unmaximize();
  preferences.minimize();
  preferences.show();
  await run(
    preferences,
    "await wait(150);check(!document.hidden,'Minimized window did not restore');check(!document.documentElement.classList.contains('window-maximized'),'Restore titlebar state is stale');return true;",
  );
  const native = await capture(preferences, "settings-restored");
  if (native && native.state !== "Normal")
    throw Error("Window did not return to Normal state");
  return {
    hover,
    attention,
    motion,
    focus,
    solid,
    nativeMotion: motionEvidence?.motion,
    nativeBoundsCalls: frames.length,
    usage,
    claudeLayout,
    settings,
    native,
  };
};
