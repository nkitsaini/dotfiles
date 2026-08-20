<script lang="ts">
  import { onMount } from 'svelte';
  import './style.css';
  import './credentials.css';

  type Repo = {
    id: string; name: string; worktree: string; git_dir: string; remote: string; branch: string;
    credential_id?: string; enabled: boolean; status: string; last_attempt?: string; last_success?: string;
    last_error?: string; ahead: number; behind: number; consecutive_failures: number;
  };
  type Credential = { id: string; name: string; kind: 'ssh'|'https'; username?: string; private_key_path?: string };
  type GithubAuthResult = { authenticated: boolean; exit_code: number|null; stdout: string; stderr: string; credentialName: string };
  type Conflict = { path: string; binary: boolean; base?: string; ours?: string; theirs?: string; result?: string };
  type Log = { timestamp: string; level: string; message: string; repository_id?: string };
  type Notice = { id: number; kind: 'success'|'error'; message: string };
  type FsEntry = { name:string; path:string; directory:boolean; size?:number };
  type Commit = { hash:string; short_hash:string; author:string; timestamp:string; subject:string };
  type BackupConfig = {
    repository: string; has_password: boolean; hostname: string; paths: string[]; excludes: string[];
    prune_opts: string[]; extra_options: string[]; status: string; last_attempt?: string;
    last_success?: string; last_error?: string;
  };
  type ResticSnapshot = {
    id: string; short_id: string; time: string; paths: string[]; hostname: string; tags?: string[];
  };

  let repos: Repo[] = [];
  let credentials: Credential[] = [];
  let logs: Log[] = [];
  let loading = true;
  let unauthorized = false;
  let error = '';
  let view: 'repos'|'credentials'|'backup'|'files'|'logs' = 'repos';
  let backupConfig: BackupConfig | null = null;
  let backupSnapshots: ResticSnapshot[] = [];
  let backupLoading = false;
  let backupRunning = false;
  let backupPathsText = '';
  let backupExcludesText = '';
  let backupPasswordInput = '';

  let showRepoForm = false;
  let showCredentialForm = false;
  let conflictRepo: Repo | null = null;
  let conflicts: Conflict[] = [];
  let selectedConflict = 0;
  let resultText = '';
  let syncing = new Set<string>();
  let browserTarget: 'worktree'|'git_dir'|null = null;
  let browserPath = '';
  let browserParent: string|null = null;
  let browserEntries: {name:string,path:string}[] = [];
  let testingCredential = '';
  let githubAuthResult: GithubAuthResult|null = null;
  let addingRepo = false;
  let cloneStatus = '';
  let repoFormError = '';
  let notices: Notice[] = [];
  let nextNoticeId = 1;
  let backendBuild = 'checking backend…';
  let notificationWarning = '';
  let gitDirMode: 'home'|'none'|'custom' = 'home';
  let filePath = '';
  let fileParent: string|null = null;
  let fileEntries: FsEntry[] = [];
  let filesLoading = false;
  let uploading = false;
  let uploadInput: HTMLInputElement;
  let commits: Record<string,Commit[]> = {};

  let repoForm = { name:'', worktree:'', git_dir:'', remote:'origin', branch:'', clone_url:'', credential_id:'' };
  let credentialForm = { name:'', kind:'ssh', username:'', secret:'', private_key:'', generate:true };

  function notify(kind:Notice['kind'],message:string) {
    const id=nextNoticeId++;
    notices=[...notices,{id,kind,message}];
    setTimeout(()=>notices=notices.filter(notice=>notice.id!==id),7000);
  }

  function actionFailed(action:string,value:unknown) {
    const detail=String(value instanceof Error?value.message:value);
    notify('error',`${action} failed: ${detail}`);
  }

  async function api(path: string, options: RequestInit = {}) {
    const response = await fetch(path, { ...options, headers: { 'Content-Type':'application/json', ...(options.headers || {}) } });
    if (response.status === 401) { unauthorized = true; throw new Error('This browser is not enrolled. Run mantis auth-link in Termux.'); }
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      const message=body.error || `${response.status} ${response.statusText}`;
      throw new Error(message);
    }
    return response.status === 204 ? null : response.json();
  }

  async function loadBackendBuild() {
    try {
      const response=await fetch(`/health?_=${Date.now()}`,{cache:'no-store'});
      if(!response.ok)throw new Error(`${response.status}`);
      const health=await response.json();
      backendBuild=`v${health.version} · build ${health.build}`;
      notificationWarning=health.notifications_available===false?'Background notifications are unavailable. Install and open the Termux:API companion app from the same source as Termux.':'';
    } catch { backendBuild='backend version unavailable'; }
  }

  async function load() {
    loading = true; error = '';
    try {
      [repos, credentials, logs] = await Promise.all([api('/api/repos'), api('/api/credentials'), api('/api/logs?limit=300')]);
      for(const repo of repos)if(!commits[repo.id])loadRecentCommits(repo.id);
      unauthorized = false;
    } catch (e) { error = String(e instanceof Error ? e.message : e); }
    finally { loading = false; }
  }

  async function addRepo() {
    error = ''; repoFormError=''; addingRepo=true; cloneStatus=repoForm.clone_url?'Starting clone…':'Adding repository…';
    try {
      await api('/api/repos', { method:'POST', body: JSON.stringify({
        ...repoForm,
        git_dir: gitDirMode==='home' ? `~/.repos/${repoForm.name.trim()}` : gitDirMode==='custom' ? repoForm.git_dir || null : null,
        branch: repoForm.branch || null,
        clone_url: repoForm.clone_url || null,
        credential_id: repoForm.credential_id || null
      })});
      showRepoForm = false; repoForm = { name:'',worktree:'',git_dir:'',remote:'origin',branch:'',clone_url:'',credential_id:'' }; gitDirMode='home'; await load();
    } catch (e) { repoFormError=String(e instanceof Error ? e.message : e); }
    finally { addingRepo=false; cloneStatus=''; }
  }

  async function removeRepo(repo: Repo) {
    if (!confirm(`Unregister ${repo.name}? No files will be deleted.`)) return;
    try { await api(`/api/repos/${repo.id}`, {method:'DELETE'}); await load(); }
    catch(e) { actionFailed(`Unregistering ${repo.name}`,e); }
  }

  async function sync(repo: Repo) {
    syncing = new Set(syncing).add(repo.id);
    repos=repos.map(item=>item.id===repo.id?{...item,status:'syncing',last_error:undefined}:item);
    try { const result=await api(`/api/repos/${repo.id}/sync`, {method:'POST', body:'{}'}); notify('success',result.disposition==='started'?'Sync started.':result.disposition==='queued'?'One follow-up sync was queued.':'This request was combined with the already queued sync.'); setTimeout(load, 900); }
    catch (e) { actionFailed(`Syncing ${repo.name}`,e); await load(); }
    finally { const next = new Set(syncing); next.delete(repo.id); syncing = next; }
  }

  async function addCredential() {
    try {
      await api('/api/credentials', {method:'POST',body:JSON.stringify({...credentialForm, secret:credentialForm.secret||null, private_key:credentialForm.private_key||null})});
      showCredentialForm=false; credentialForm={name:'',kind:'ssh',username:'',secret:'',private_key:'',generate:true}; await load();
    } catch (e) { actionFailed('Adding credential',e); }
  }

  async function browsePath(path?: string) {
    try {
      const data=await api(`/api/fs${path?`?path=${encodeURIComponent(path)}`:''}`);
      browserPath=data.path; browserParent=data.parent; browserEntries=data.entries;
    } catch(e) { actionFailed('Opening folder',e); }
  }
  async function openBrowser(target:'worktree'|'git_dir') { browserTarget=target; if(target==='git_dir')gitDirMode='custom'; await browsePath(repoForm[target]||undefined); }
  function chooseDirectory() { if(browserTarget)repoForm[browserTarget]=browserPath; browserTarget=null; }
  async function createPickerFolder() {
    const name=prompt('New folder name'); if(!name)return;
    try { await api('/api/fs/directory',{method:'POST',body:JSON.stringify({parent:browserPath,name})}); await browsePath(browserPath); notify('success',`Created ${name}.`); }
    catch(e) { actionFailed('Creating folder',e); }
  }

  async function browseFiles(path?:string) {
    filesLoading=true;
    try {
      const data=await api(`/api/files${path?`?path=${encodeURIComponent(path)}`:''}`);
      filePath=data.path; fileParent=data.parent; fileEntries=data.entries;
    } catch(e) { actionFailed('Opening files',e); }
    finally { filesLoading=false; }
  }
  function openFiles() { view='files'; if(!filePath)browseFiles(); }
  async function createFileFolder() {
    const name=prompt('New folder name'); if(!name)return;
    try { await api('/api/files/directory',{method:'POST',body:JSON.stringify({parent:filePath,name})}); await browseFiles(filePath); notify('success',`Created ${name}.`); }
    catch(e) { actionFailed('Creating folder',e); }
  }
  async function copyPath(path:string) {
    try { await navigator.clipboard.writeText(path); notify('success','Full path copied.'); }
    catch(e) { actionFailed('Copying path',e); }
  }
  async function uploadFiles(event:Event) {
    const input=event.currentTarget as HTMLInputElement;
    const selected=Array.from(input.files||[]); if(!selected.length)return;
    uploading=true;
    try {
      for(const file of selected) {
        if(fileEntries.some(entry=>entry.name===file.name)&&!confirm(`${file.name} already exists. Replace it?`))continue;
        const response=await fetch(`/api/files/upload?path=${encodeURIComponent(filePath)}&name=${encodeURIComponent(file.name)}`,{method:'PUT',headers:{'Content-Type':'application/octet-stream'},body:file});
        if(!response.ok) { const body=await response.json().catch(()=>({})); throw new Error(body.error||`${response.status} ${response.statusText}`); }
      }
      await browseFiles(filePath); notify('success',`${selected.length} file${selected.length===1?'':'s'} uploaded.`);
    } catch(e) { actionFailed('Uploading files',e); }
    finally { uploading=false; input.value=''; }
  }
  function formatSize(size?:number) {
    if(size===undefined)return '';
    if(size<1024)return `${size} B`; if(size<1048576)return `${(size/1024).toFixed(1)} KB`; return `${(size/1048576).toFixed(1)} MB`;
  }
  async function loadRecentCommits(id:string) {
    try { const value=await api(`/api/repos/${id}/commits?limit=3`); commits={...commits,[id]:value}; }
    catch { commits={...commits,[id]:[]}; }
  }

  async function removeCredential(id: string) {
    if (!confirm('Remove this credential profile?')) return;
    try { await api(`/api/credentials/${id}`,{method:'DELETE'}); await load(); } catch(e) { actionFailed('Removing credential',e); }
  }
  async function copyPublicKey(id:string) { try { const data=await api(`/api/credentials/${id}/public-key`); await navigator.clipboard.writeText(data.public_key); notify('success','Public key copied.'); } catch(e) { actionFailed('Copying public key',e); } }
  async function trustHost(id:string) { const host=prompt('SSH hostname to verify','github.com'); if(!host)return; try { const data=await api(`/api/credentials/${id}/host-key/scan`,{method:'POST',body:JSON.stringify({host})}); if(confirm(`Verify these SSH fingerprints independently before trusting them:\n\n${data.fingerprints.join('\n')}\n\nTrust this host?`)){ await api(`/api/credentials/${id}/host-key`,{method:'PUT',body:JSON.stringify({keys:data.keys})}); notify('success',`${host} was saved to this credential's known_hosts file.`); } } catch(e) { actionFailed(`Trusting ${host}`,e); } }
  async function testGithub(item:Credential) {
    testingCredential=item.id; error='';
    try {
      const data=await api(`/api/credentials/${item.id}/test-github`,{method:'POST',body:'{}'});
      githubAuthResult={...data,credentialName:item.name};
    } catch(e) { actionFailed('Testing GitHub authentication',e); }
    finally { testingCredential=''; }
  }

  async function openConflicts(repo: Repo) {
    try {
      const data = await api(`/api/repos/${repo.id}/conflicts`); conflictRepo=repo; conflicts=data.files; selectedConflict=0; resultText=conflicts[0]?.result||'';
    } catch(e) { actionFailed(`Opening conflicts for ${repo.name}`,e); }
  }

  function selectConflict(index: number) { selectedConflict=index; resultText=conflicts[index]?.result||''; }
  function choose(side: 'ours'|'theirs'|'both') {
    const file=conflicts[selectedConflict];
    resultText = side==='ours' ? file.ours||'' : side==='theirs' ? file.theirs||'' : `${file.ours||''}${file.ours?.endsWith('\n')?'':'\n'}${file.theirs||''}`;
  }
  function markerChunks(text: string) {
    const regex=/<<<<<<<[^\n]*\n([\s\S]*?)=======\n([\s\S]*?)>>>>>>>[^\n]*(?:\n|$)/g; const chunks=[]; let match;
    while((match=regex.exec(text))) chunks.push({start:match.index,end:regex.lastIndex,ours:match[1],theirs:match[2]});
    return chunks;
  }
  function resolveChunk(index:number, side:'ours'|'theirs'|'both') {
    const chunk=markerChunks(resultText)[index]; if(!chunk)return;
    const replacement=side==='ours'?chunk.ours:side==='theirs'?chunk.theirs:chunk.ours+chunk.theirs;
    resultText=resultText.slice(0,chunk.start)+replacement+resultText.slice(chunk.end);
  }
  async function saveConflict(choice?:'ours'|'theirs') {
    if(!conflictRepo)return; const file=conflicts[selectedConflict];
    try {
      await api(`/api/repos/${conflictRepo.id}/conflicts/resolve`,{method:'PUT',body:JSON.stringify(choice?{path:file.path,choice}:{path:file.path,content:resultText})});
      await openConflicts(conflictRepo);
    } catch(e) { actionFailed(`Resolving ${file.path}`,e); }
  }
  async function finishMerge() { if(!conflictRepo)return; try { await api(`/api/repos/${conflictRepo.id}/merge/continue`,{method:'POST',body:'{}'}); conflictRepo=null; await load(); } catch(e) { actionFailed('Finishing merge',e); } }
  async function abortMerge() { if(!conflictRepo||!confirm('Abort this merge and restore the pre-merge state?'))return; try { await api(`/api/repos/${conflictRepo.id}/merge/abort`,{method:'POST',body:'{}'}); conflictRepo=null; await load(); } catch(e) { actionFailed('Aborting merge',e); } }

  async function loadBackup() {
    backupLoading = true;
    try {
      backupConfig = await api('/api/backup/config');
      if (backupConfig) {
        backupPathsText = backupConfig.paths.join('\n');
        backupExcludesText = backupConfig.excludes.join('\n');
      }
      backupSnapshots = await api('/api/backup/snapshots').catch(() => []);
    } catch (e) {
      actionFailed('Loading backup config', e);
    } finally {
      backupLoading = false;
    }
  }

  async function saveBackupConfig() {
    if (!backupConfig) return;
    try {
      const paths = backupPathsText.split('\n').map(s => s.trim()).filter(Boolean);
      const excludes = backupExcludesText.split('\n').map(s => s.trim()).filter(Boolean);
      const payload: any = {
        repository: backupConfig.repository,
        hostname: backupConfig.hostname || 'mantis',
        paths,
        excludes,
      };
      if (backupPasswordInput) {
        payload.password = backupPasswordInput;
      }
      backupConfig = await api('/api/backup/config', {
        method: 'PUT',
        body: JSON.stringify(payload),
      });
      backupPasswordInput = '';
      notify('success', 'Backup configuration saved.');
    } catch (e) {
      actionFailed('Saving backup configuration', e);
    }
  }

  async function triggerBackup() {
    backupRunning = true;
    try {
      await api('/api/backup/trigger', { method: 'POST', body: '{}' });
      notify('success', 'Restic backup started in background.');
      setTimeout(loadBackup, 1500);
    } catch (e) {
      actionFailed('Triggering backup', e);
    } finally {
      backupRunning = false;
    }
  }

  async function initBackupRepo() {
    try {
      const res = await api('/api/backup/init', { method: 'POST', body: '{}' });
      notify('success', res.message || 'Repository initialized.');
      await loadBackup();
    } catch (e) {
      actionFailed('Initializing restic repository', e);
    }
  }

  async function pruneBackup() {
    try {
      await api('/api/backup/prune', { method: 'POST', body: '{}' });
      notify('success', 'Prune completed.');
      await loadBackup();
    } catch (e) {
      actionFailed('Pruning snapshots', e);
    }
  }

  async function checkBackupRepo() {
    try {
      await api('/api/backup/check', { method: 'POST', body: '{}' });
      notify('success', 'Restic check verified repository integrity.');
    } catch (e) {
      actionFailed('Checking repository', e);
    }
  }

  function relative(value?:string) { if(!value)return 'Never'; const normalized=/Z$|[+-]\d\d:\d\d$/.test(value)?value:value+'Z'; const ms=Date.now()-new Date(normalized).getTime(); const minutes=Math.max(0,Math.floor(ms/60000)); return minutes<1?'Just now':minutes<60?`${minutes}m ago`:minutes<1440?`${Math.floor(minutes/60)}h ago`:`${Math.floor(minutes/1440)}d ago`; }
  function statusLabel(status:string) { return status.replace('_',' '); }


  onMount(() => {
    loadBackendBuild();
    load();
    const events = new EventSource('/api/events');
    events.addEventListener('log', e => { try { const log=JSON.parse((e as MessageEvent).data); logs=[...logs.slice(-499),log]; if(addingRepo&&log.message?.startsWith('Clone:'))cloneStatus=log.message.slice(6).trim(); if(log.repository_id&&(log.message==='Synchronization started'||log.message==='Synchronization completed'||log.level==='error'))setTimeout(load,200); if(log.repository_id&&['Synchronization completed','Pushed local commits','Committed local text changes'].includes(log.message))loadRecentCommits(log.repository_id); } catch {} });
    const timer=setInterval(load,10000);
    return()=>{events.close();clearInterval(timer)};
  });
</script>

<svelte:head><title>Mantis · Repository sync</title></svelte:head>

<div class="shell">
  <header>
    <a class="brand" href="/" aria-label="Mantis home"><span class="mark">M</span><span>Mantis<small>Repository sync</small></span></a>
    <div class="header-actions"><span class="build-id">{backendBuild}</span><button class="icon-button" onclick={()=>{loadBackendBuild();load()}} title="Refresh">↻</button></div>
  </header>

  <main>
    {#if unauthorized}
      <section class="empty auth"><div class="empty-icon">⌁</div><h1>Enroll this browser</h1><p>Run <code>mantis auth-link</code> in Termux, then open the one-time URL it prints.</p></section>
    {:else}
      <section class="hero">
        <div><p class="eyebrow">SYSTEM OVERVIEW</p><h1>{repos.filter(r=>r.status==='idle').length}<span> / {repos.length} repositories healthy</span></h1></div>
        <button class="primary" onclick={async()=>{for(const repo of repos)await sync(repo)}}>Sync everything</button>
      </section>
      {#if error}<div class="alert"><span>!</span><p>{error}</p><button onclick={()=>error=''}>×</button></div>{/if}
      {#if notificationWarning}<div class="alert warning-alert"><span>!</span><p>{notificationWarning}</p><button onclick={()=>notificationWarning=''}>×</button></div>{/if}

      <nav class="tabs" aria-label="Sections">
        <button class:active={view==='repos'} onclick={()=>view='repos'}>Repositories <b>{repos.length}</b></button>
        <button class:active={view==='credentials'} onclick={()=>view='credentials'}>Credentials <b>{credentials.length}</b></button>
        <button class:active={view==='backup'} onclick={()=>{view='backup';loadBackup()}}>Backup</button>
        <button class:active={view==='files'} onclick={openFiles}>Files</button>
        <button class:active={view==='logs'} onclick={()=>view='logs'}>Activity</button>
      </nav>

      {#if loading && repos.length===0}<div class="loading">Loading Mantis…</div>{/if}
      {#if view==='repos'}
        <div class="section-heading"><div><h2>Repositories</h2><p>Local worktrees managed by Mantis</p></div><button class="secondary" onclick={()=>showRepoForm=true}>＋ Add repository</button></div>
        {#if repos.length===0&&!loading}<section class="empty"><div class="empty-icon">⑂</div><h2>No repositories yet</h2><p>Add an existing worktree or clone one with detached Git metadata.</p><button class="primary" onclick={()=>showRepoForm=true}>Add your first repository</button></section>{/if}
        <div class="repo-grid">
          {#each repos as repo}
            <article class="repo-card" class:attention={repo.status!=='idle'}>
              <div class="repo-top"><span class="status-dot {repo.status}"></span><div><h3>{repo.name}</h3><p>{repo.remote}/{repo.branch}</p></div><span class="badge {repo.status}">{statusLabel(repo.status)}</span></div>
              <dl><div><dt>LAST SYNC</dt><dd>{relative(repo.last_success)}</dd></div><div><dt>DIVERGENCE</dt><dd>↑ {repo.ahead} &nbsp; ↓ {repo.behind}</dd></div></dl>
              <div class="path" title={repo.worktree}>⌂ {repo.worktree}</div>
              <div class="recent-commits"><p>RECENT COMMITS</p>{#if commits[repo.id]?.length}{#each commits[repo.id] as commit}<div title={commit.hash}><code>{commit.short_hash}</code><span><b>{commit.subject}</b><small>{commit.author} · {relative(commit.timestamp)}</small></span></div>{/each}{:else}<span class="commit-empty">No commits yet</span>{/if}</div>
              {#if repo.last_error}<div class="repo-error"><strong>LAST SYNC ERROR</strong><p>{repo.last_error}</p></div>{/if}
              <footer>
                {#if repo.status==='needs_attention'}<button class="warning" onclick={()=>openConflicts(repo)}>Resolve conflicts</button>{/if}
                <button class="sync-button" disabled={syncing.has(repo.id)} onclick={()=>sync(repo)}>{syncing.has(repo.id)?'Submitting…':repo.status==='syncing'?'＋ Queue follow-up':'↻ Sync now'}</button>
                <button class="more" onclick={()=>removeRepo(repo)} title="Unregister">⋯</button>
              </footer>
            </article>
          {/each}
        </div>
      {:else if view==='credentials'}
        <div class="section-heading"><div><h2>Credentials</h2><p>Dedicated SSH keys and HTTPS tokens</p></div><button class="secondary" onclick={()=>showCredentialForm=true}>＋ Add credential</button></div>
        <div class="credential-list">{#each credentials as item}<article><span class="credential-icon">{item.kind==='ssh'?'⌘':'◈'}</span><div><h3>{item.name}</h3><p>{item.kind.toUpperCase()} · {item.username||'dedicated key'}</p></div>{#if item.kind==='ssh'}<button class="credential-action" onclick={()=>copyPublicKey(item.id)}>Copy public key</button><button class="credential-action" onclick={()=>trustHost(item.id)}>Trust host</button><button class="credential-action" disabled={testingCredential===item.id} onclick={()=>testGithub(item)}>{testingCredential===item.id?'Testing…':'Test GitHub auth'}</button>{/if}<button class="more" onclick={()=>removeCredential(item.id)}>×</button></article>{/each}</div>
        {#if credentials.length===0}<section class="empty"><h2>No credentials</h2><p>Repositories can still use your existing Git and SSH configuration.</p></section>{/if}
      {:else if view==='backup'}
        <div class="section-heading">
          <div><h2>Restic Backup</h2><p>Direct encrypted device backups for Termux storage</p></div>
          <div class="file-actions">
            <button class="secondary" onclick={initBackupRepo}>Init repository</button>
            <button class="secondary" onclick={checkBackupRepo}>Check</button>
            <button class="secondary" onclick={pruneBackup}>Prune</button>
            <button class="primary" disabled={backupRunning || backupConfig?.status==='backing_up'} onclick={triggerBackup}>
              {backupRunning || backupConfig?.status==='backing_up' ? 'Backing up…' : 'Backup now'}
            </button>
          </div>
        </div>

        {#if backupConfig}
          <div class="repo-grid" style="margin-bottom: 24px;">
            <article class="repo-card">
              <div class="repo-top">
                <span class="status-dot {backupConfig.status}"></span>
                <div>
                  <h3>Status</h3>
                  <p>Host: {backupConfig.hostname || 'mantis'}</p>
                </div>
                <span class="badge {backupConfig.status}">{statusLabel(backupConfig.status)}</span>
              </div>
              <dl>
                <div>
                  <dt>LAST BACKUP</dt>
                  <dd>{relative(backupConfig.last_success)}</dd>
                </div>
                <div>
                  <dt>SNAPSHOTS</dt>
                  <dd>{backupSnapshots.length}</dd>
                </div>
              </dl>
              <div class="path" title={backupConfig.repository}>⌂ {backupConfig.repository || 'No repository configured'}</div>
              {#if backupConfig.last_error}
                <div class="repo-error" style="margin-top: 10px;"><strong>LAST BACKUP ERROR</strong><p>{backupConfig.last_error}</p></div>
              {/if}
            </article>
            
            <article class="repo-card">
              <div class="repo-top"><div><h3>Configuration</h3><p>Settings stored securely in Mantis</p></div></div>
              <form onsubmit={(e)=>{e.preventDefault();saveBackupConfig()}} style="margin-top: 12px; display: grid; gap: 10px;">
                <label style="font-size: 11px; color: var(--muted); margin: 0;">
                  Repository URL
                  <input style="margin-top: 4px; width: 100%; border: 1px solid var(--line); background: #0f120e; color: #eaf1e6; border-radius: 8px; padding: 8px 10px; font-size: 12px;" bind:value={backupConfig.repository} placeholder="sftp:box-interactive:/home/backups/mantis/restic" />
                </label>
                <div class="form-row">
                  <label style="font-size: 11px; color: var(--muted); margin: 0;">
                    Password
                    <input type="password" style="margin-top: 4px; width: 100%; border: 1px solid var(--line); background: #0f120e; color: #eaf1e6; border-radius: 8px; padding: 8px 10px; font-size: 12px;" bind:value={backupPasswordInput} placeholder={backupConfig.has_password ? "(password set)" : "Enter password"} />
                  </label>
                  <label style="font-size: 11px; color: var(--muted); margin: 0;">
                    Hostname
                    <input style="margin-top: 4px; width: 100%; border: 1px solid var(--line); background: #0f120e; color: #eaf1e6; border-radius: 8px; padding: 8px 10px; font-size: 12px;" bind:value={backupConfig.hostname} placeholder="mantis" />
                  </label>
                </div>
                <label style="font-size: 11px; color: var(--muted); margin: 0;">
                  Backup Paths (one per line)
                  <textarea rows="3" style="margin-top: 4px; width: 100%; border: 1px solid var(--line); background: #0f120e; color: #eaf1e6; border-radius: 8px; padding: 8px 10px; font: 11px ui-monospace,monospace;" bind:value={backupPathsText}></textarea>
                </label>
                <label style="font-size: 11px; color: var(--muted); margin: 0;">
                  Exclude Patterns (one per line)
                  <textarea rows="2" style="margin-top: 4px; width: 100%; border: 1px solid var(--line); background: #0f120e; color: #eaf1e6; border-radius: 8px; padding: 8px 10px; font: 11px ui-monospace,monospace;" bind:value={backupExcludesText}></textarea>
                </label>
                <button type="submit" class="primary" style="margin-top: 4px;">Save Settings</button>
              </form>
            </article>
          </div>

          <div class="section-heading" style="margin-top: 24px;">
            <div><h2>Recent Snapshots</h2><p>{backupSnapshots.length} snapshot{backupSnapshots.length===1?'':'s'} in repository</p></div>
            <button class="secondary" onclick={loadBackup}>↻ Refresh</button>
          </div>

          {#if backupSnapshots.length === 0}
            <div class="loading">No snapshots found in repository.</div>
          {:else}
            <div class="file-list" style="border: 1px solid var(--line); border-radius: 12px; background: #10130f;">
              {#each backupSnapshots as snap}
                <div class="file-row" style="grid-template-columns: 85px 180px 90px 1fr; font-size: 12px;">
                  <code style="color: var(--green);">{snap.short_id || snap.id.slice(0, 8)}</code>
                  <span>{new Date(snap.time).toLocaleString()}</span>
                  <small style="text-align: left;">{snap.hostname}</small>
                  <span style="color: var(--muted); font: 11px ui-monospace,monospace; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">{snap.paths.join(', ')}</span>
                </div>
              {/each}
            </div>
          {/if}
        {:else}
          <div class="loading">Loading backup configuration…</div>
        {/if}
      {:else if view==='files'}
        <div class="section-heading"><div><h2>Files</h2><p>Browse files available to Termux</p></div><div class="file-actions"><button class="secondary" onclick={createFileFolder}>＋ New folder</button><button class="primary" disabled={uploading} onclick={()=>uploadInput.click()}>{uploading?'Uploading…':'↑ Upload'}</button><input class="hidden-upload" bind:this={uploadInput} type="file" multiple onchange={uploadFiles}/></div></div>
        <div class="file-browser">
          <div class="file-toolbar"><code>{filePath||'Loading…'}</code>{#if filePath}<button onclick={()=>copyPath(filePath)}>Copy path</button>{/if}</div>
          {#if filesLoading}<div class="loading">Loading files…</div>{:else}<div class="file-list">
            {#if fileParent}<button class="file-row" onclick={()=>browseFiles(fileParent!)}><span class="file-name"><span class="file-icon">↰</span><b>Parent directory</b></span><small></small><span></span></button>{/if}
            {#each fileEntries as entry}<div class="file-row"><button class="file-name" onclick={()=>entry.directory&&browseFiles(entry.path)}><span class="file-icon">{entry.directory?'▱':'▤'}</span><b>{entry.name}</b></button><small>{entry.directory?'Folder':formatSize(entry.size)}</small><div><button title="Copy full path" onclick={()=>copyPath(entry.path)}>Copy path</button>{#if !entry.directory}<a href={`/api/files/download?path=${encodeURIComponent(entry.path)}`} download={entry.name}>Download</a>{/if}</div></div>{/each}
            {#if !fileEntries.length&&!fileParent}<div class="loading">This directory is empty.</div>{/if}
          </div>{/if}
        </div>
      {:else}
        <div class="section-heading"><div><h2>Activity</h2><p>Live structured service log</p></div><span class="live"><i></i> LIVE</span></div>
        <div class="logs">{#each [...logs].reverse() as log}<div class="log-row"><time>{new Date(log.timestamp).toLocaleString()}</time><span class="level {log.level}">{log.level}</span><p>{log.message}</p></div>{/each}</div>
      {/if}
    {/if}
  </main>
</div>

{#if notices.length}<div class="notice-stack" aria-live="assertive">{#each notices as notice (notice.id)}<div class="notice {notice.kind}"><span>{notice.kind==='success'?'✓':'!'}</span><p>{notice.message}</p><button aria-label="Dismiss notification" onclick={()=>notices=notices.filter(item=>item.id!==notice.id)}>×</button></div>{/each}</div>{/if}

{#if showRepoForm}
  <div class="modal-backdrop" role="presentation" onclick={(e)=>e.target===e.currentTarget&&!addingRepo&&(showRepoForm=false)}><form class="modal" onsubmit={(e)=>{e.preventDefault();addRepo()}}><header><div><p class="eyebrow">REPOSITORY</p><h2>Add to Mantis</h2></div><button type="button" disabled={addingRepo} onclick={()=>showRepoForm=false}>×</button></header>
    <label>Name<input required bind:value={repoForm.name} placeholder="Notes" /></label>
    <label>Clone URL <small>Leave blank for an existing repository</small><input bind:value={repoForm.clone_url} placeholder="git@github.com:you/notes.git" /></label>
    <label>Content directory<div class="field-picker"><input required bind:value={repoForm.worktree} placeholder="/storage/emulated/0/Documents/Notes" /><button type="button" onclick={()=>openBrowser('worktree')}>Browse</button></div></label>
    <label>Git metadata location<select bind:value={gitDirMode}><option value="home">Separate directory under ~/.repos (recommended)</option><option value="none">Do not use a separate Git directory</option><option value="custom">Provide a full path</option></select></label>
    {#if gitDirMode==='home'}<div class="git-dir-preview"><small>Git directory</small><code>~/.repos/{repoForm.name.trim()||'{repository_name}'}</code></div>
    {:else if gitDirMode==='custom'}<label>Git directory<div class="field-picker"><input required bind:value={repoForm.git_dir} placeholder="/full/path/to/git-metadata" /><button type="button" onclick={()=>openBrowser('git_dir')}>Browse</button></div></label>{/if}
    <div class="form-row"><label>Remote<input bind:value={repoForm.remote}/></label><label>Branch<input bind:value={repoForm.branch} placeholder="auto-detect"/></label></div>
    <label>Credential<select bind:value={repoForm.credential_id}><option value="">Existing Git configuration</option>{#each credentials as c}<option value={c.id}>{c.name}</option>{/each}</select></label>
    {#if repoFormError}<div class="form-error"><strong>Could not add repository</strong><p>{repoFormError}</p></div>{/if}
    {#if addingRepo}<div class="clone-progress"><span></span><div><strong>{repoForm.clone_url?'Cloning repository':'Adding repository'}</strong><p>{cloneStatus}</p></div></div>{/if}
    <footer><button type="button" class="ghost" disabled={addingRepo} onclick={()=>showRepoForm=false}>Cancel</button><button class="primary" disabled={addingRepo}>{addingRepo?(repoForm.clone_url?'Cloning…':'Adding…'):'Add repository'}</button></footer>
  </form></div>
{/if}

{#if browserTarget}
  <div class="modal-backdrop directory-layer" role="presentation"><section class="modal directory"><header><div><p class="eyebrow">FOLDER</p><h2>Choose {browserTarget==='worktree'?'content':'Git metadata'} directory</h2></div><button onclick={()=>browserTarget=null}>×</button></header>
    <div class="browser-path">{browserPath}</div>
    <div class="browser-list">{#if browserParent}<button onclick={()=>browsePath(browserParent!)}><span>↰</span><b>Parent directory</b></button>{/if}{#each browserEntries as entry}<button onclick={()=>browsePath(entry.path)}><span>▱</span><b>{entry.name}</b></button>{/each}</div>
    <footer><button class="secondary browser-create" onclick={createPickerFolder}>＋ New folder</button><span></span><button class="ghost" onclick={()=>browserTarget=null}>Cancel</button><button class="primary" onclick={chooseDirectory}>Choose this folder</button></footer>
  </section></div>
{/if}

{#if showCredentialForm}
  <div class="modal-backdrop" role="presentation"><form class="modal" onsubmit={(e)=>{e.preventDefault();addCredential()}}><header><div><p class="eyebrow">CREDENTIAL</p><h2>Add authentication</h2></div><button type="button" onclick={()=>showCredentialForm=false}>×</button></header>
    <label>Name<input required bind:value={credentialForm.name} placeholder="GitHub personal"/></label>
    <label>Type<select bind:value={credentialForm.kind}><option value="ssh">SSH key</option><option value="https">HTTPS token</option></select></label>
    {#if credentialForm.kind==='ssh'}<label class="check"><input type="checkbox" bind:checked={credentialForm.generate}/> Generate a dedicated Ed25519 key</label>{#if !credentialForm.generate}<label>Private key<textarea rows="6" bind:value={credentialForm.private_key}></textarea></label>{/if}
    {:else}<label>Username<input required bind:value={credentialForm.username}/></label><label>Personal access token<input required type="password" bind:value={credentialForm.secret}/></label>{/if}
    <footer><button type="button" class="ghost" onclick={()=>showCredentialForm=false}>Cancel</button><button class="primary">Save credential</button></footer>
  </form></div>
{/if}

{#if githubAuthResult}
  <div class="modal-backdrop" role="presentation" onclick={(e)=>e.target===e.currentTarget&&(githubAuthResult=null)}><section class="modal auth-test-result"><header><div><p class="eyebrow">SSH AUTHENTICATION</p><h2>{githubAuthResult.authenticated?'GitHub authentication works':'GitHub authentication failed'}</h2></div><button onclick={()=>githubAuthResult=null}>×</button></header>
    <p class:success={githubAuthResult.authenticated} class:failure={!githubAuthResult.authenticated}>{githubAuthResult.authenticated?`${githubAuthResult.credentialName} was accepted by GitHub.`:`GitHub did not accept ${githubAuthResult.credentialName}.`}</p>
    <pre>{[githubAuthResult.stdout,githubAuthResult.stderr].filter(Boolean).join('\n')||`ssh exited with status ${githubAuthResult.exit_code??'unknown'}`}</pre>
    {#if !githubAuthResult.authenticated}<small>If the output mentions host-key verification, use “Trust host” for github.com first. Otherwise, copy the public key and add it to your GitHub account.</small>{/if}
    <footer><button class="primary" onclick={()=>githubAuthResult=null}>Close</button></footer>
  </section></div>
{/if}

{#if conflictRepo}
  <div class="resolver"><header><div><p class="eyebrow">MERGE IN PROGRESS</p><h2>{conflictRepo.name}</h2></div><div><button class="danger" onclick={abortMerge}>Abort merge</button><button class="primary" disabled={conflicts.length>0} onclick={finishMerge}>Commit & push</button><button class="icon-button" onclick={()=>conflictRepo=null}>×</button></div></header>
    <div class="resolver-body"><aside><h3>Conflicted files <b>{conflicts.length}</b></h3>{#each conflicts as file,i}<button class:active={i===selectedConflict} onclick={()=>selectConflict(i)}><span>{file.binary?'◆':'≡'}</span>{file.path}</button>{/each}</aside>
      {#if conflicts.length}<section class="editor"><div class="editor-head"><strong>{conflicts[selectedConflict].path}</strong><div><button onclick={()=>choose('ours')}>Use ours</button><button onclick={()=>choose('theirs')}>Use theirs</button><button onclick={()=>choose('both')}>Keep both</button></div></div>
        {#if conflicts[selectedConflict].binary}<div class="binary-choice"><h3>Binary file</h3><p>This file cannot be edited as text. Choose one complete version.</p><button class="secondary" onclick={()=>saveConflict('ours')}>Keep ours</button><button class="secondary" onclick={()=>saveConflict('theirs')}>Keep theirs</button></div>
        {:else}<div class="versions"><details><summary>Base</summary><pre>{conflicts[selectedConflict].base}</pre></details><details><summary>Ours</summary><pre>{conflicts[selectedConflict].ours}</pre></details><details><summary>Theirs</summary><pre>{conflicts[selectedConflict].theirs}</pre></details></div>
          {#if markerChunks(resultText).length}<div class="chunks">{#each markerChunks(resultText) as _,i}<span>Conflict {i+1}</span><button onclick={()=>resolveChunk(i,'ours')}>Ours</button><button onclick={()=>resolveChunk(i,'theirs')}>Theirs</button><button onclick={()=>resolveChunk(i,'both')}>Both</button>{/each}</div>{/if}
          <textarea class="code-editor" spellcheck="false" bind:value={resultText}></textarea><footer><span>{markerChunks(resultText).length} unresolved markers</span><button class="primary" disabled={markerChunks(resultText).length>0} onclick={()=>saveConflict()}>Mark resolved</button></footer>{/if}
      </section>{:else}<section class="empty"><h2>Every file is resolved</h2><p>Commit the merge and push it to the remote.</p><button class="primary" onclick={finishMerge}>Commit & push</button></section>{/if}
    </div>
  </div>
{/if}
