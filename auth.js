/* StudyPilot account UI and per-user cloud storage. Data access is additionally restricted by Supabase RLS. */
(() => {
  'use strict';
  const $ = (s) => document.querySelector(s);
  const cfg = window.STUDYPILOT_CONFIG || {};
  const configured = /^https:\/\/.+\.supabase\.co\/?$/.test(String(cfg.SUPABASE_URL || '')) && String(cfg.SUPABASE_PUBLIC_KEY || '').length > 20 && !String(cfg.SUPABASE_URL).includes('PASTE_') && !String(cfg.SUPABASE_PUBLIC_KEY).includes('PASTE_');
  let client = null, currentUser = null, authMode = 'signin', syncTimer = null, isApplyingCloud = false;
  const dialog = $('#accountDialog');
  function msg(text, error=false){const el=$('#authMessage'); if(el){el.textContent=text;el.classList.toggle('error',error)}}
  function setSaveLabel(text, error=false){const el=$('#saveState');if(el){el.textContent=text;el.dataset.state=/loading|syncing/i.test(text)?'busy':'idle';el.classList.toggle('save-error',error)}}
  function showDialog(){if(!dialog.open)dialog.showModal();renderAccount()}
  function setMode(mode){authMode=mode;$('#accountSignedOut').hidden=false;$('#accountSignedIn').hidden=true;$('#accountNameField').hidden=mode!=='signup';$('#accountDialogTitle').textContent=mode==='signup'?'Create your student account':'Sign in to StudyPilot';$('#accountDialogDescription').textContent=mode==='signup'?'Create one account to keep your revision plan private and available across devices.':'Your revision plan follows your account across devices.';$('#authSubmit').textContent=mode==='signup'?'Create account':'Sign in';$('#authToggleMode').textContent=mode==='signup'?'I already have an account':'Create a student account';$('#authForgotPassword').hidden=mode==='signup';msg('')}
  function initials(name){return String(name||'Student').trim().split(/\s+/).slice(0,2).map(x=>x[0]||'').join('').toUpperCase()||'SP'}
  function setAvatar(el, avatar, name){if(!el)return;el.replaceChildren();if(typeof avatar==='string'&&avatar.startsWith('data:image/')){const img=document.createElement('img');img.className='avatar-image';img.alt='';img.src=avatar;el.appendChild(img)}else el.textContent=initials(name)}
  function renderAccount(){const data=window.StudyPilot?.getData?.()||{profile:{}};const p=data.profile||{};const displayName=p.name||currentUser?.user_metadata?.full_name||currentUser?.email?.split('@')[0]||'Student';setAvatar($('#accountAvatar'),p.avatar,displayName);$('#accountName').textContent=currentUser?displayName:'Sign in';$('#accountCaption').textContent=currentUser?(currentUser.email||'Account connected'):'Sync your study data';$('#settingsAccountStatus').textContent=currentUser?`Signed in as ${currentUser.email}. Cloud sync is enabled.`:(configured?'Not signed in. Sign in to sync your study data.':'Site configuration is incomplete.');$('#signedInName').textContent=displayName;$('#signedInEmail').textContent=currentUser?.email||'';$('#signedInSyncStatus').textContent=currentUser?'Your study data is stored in your private account.':'Cloud sync is not connected.';setAvatar($('#dialogAvatarPreview'),p.avatar,displayName);if(currentUser){$('#accountSignedOut').hidden=true;$('#accountSignedIn').hidden=false;$('#accountDialogTitle').textContent='Your account';$('#accountDialogDescription').textContent='Your account and private study data.';msg('')}else{setMode(authMode)} }
  async function syncNow(snapshot){if(!client||!currentUser||isApplyingCloud)return;try{setSaveLabel('Syncing…');const payload={user_id:currentUser.id,data:snapshot,updated_at:new Date().toISOString()};const {error}=await client.from('studypilot_user_data').upsert(payload,{onConflict:'user_id'});if(error)throw error;setSaveLabel('Saved to cloud');$('#signedInSyncStatus').textContent='Your study data is synced securely.';$('#settingsAccountStatus').textContent=`Signed in as ${currentUser.email}. Cloud sync is up to date.`}catch(e){console.error('StudyPilot cloud save failed',e);setSaveLabel('Cloud save failed',true);$('#signedInSyncStatus').textContent='Cloud save failed. Your planner is only in memory until cloud saving succeeds.';$('#settingsAccountStatus').textContent='Cloud save failed: '+(e.message||'Check the database table and RLS policies.');msg('Cloud save failed. Your changes are not saved. Check the database setup and try again.',true)}}
  function scheduleSync(snapshot){if(!client||!currentUser||isApplyingCloud)return;clearTimeout(syncTimer);syncTimer=setTimeout(()=>syncNow(snapshot),700)}
  async function loadStudentData(user){currentUser=user;clearTimeout(syncTimer);isApplyingCloud=true;window.StudyPilot.replaceData(window.StudyPilot.freshData());isApplyingCloud=false;renderAccount();try{setSaveLabel('Loading cloud…');const {data:row,error}=await client.from('studypilot_user_data').select('data').eq('user_id',user.id).maybeSingle();if(error)throw error;isApplyingCloud=true;if(row&&row.data&&typeof row.data==='object'){window.StudyPilot.replaceData(row.data)}else{
      // A new account must never inherit data left in the page by another account.
      // Do not offer browser-data migration: start with a clean planner for this user.
      const fresh=window.StudyPilot.freshData();
      fresh.profile.name=user.user_metadata?.full_name||user.email?.split('@')[0]||'Student';
      window.StudyPilot.replaceData(fresh);
    }isApplyingCloud=false;await syncNow(window.StudyPilot.getData());renderAccount();if(dialog.open)renderAccount();await refreshCentralSubjectChoices();await refreshNoticeboard();await refreshSuggestionSubjects();await loadMySuggestions();await loadStudentResources()}catch(e){isApplyingCloud=false;console.error('StudyPilot cloud load failed',e);setSaveLabel('Cloud connection error',true);msg('We could not load your study data. Please try again shortly or contact support.',true);$('#settingsAccountStatus').textContent='Cloud data could not be loaded. Please contact support if this continues.';renderAccount()}}
  async function signOut(){if(!client)return;const {error}=await client.auth.signOut();if(error){console.error('StudyPilot sign-out failed',error);msg('We could not sign out. Please try again.',true);return}currentUser=null;isApplyingCloud=true;window.StudyPilot.replaceData(window.StudyPilot.freshData());isApplyingCloud=false;renderAccount();await refreshNoticeboard();await loadMySuggestions();await loadStudentResources();msg('You have signed out. Your cloud copy remains saved; this screen has been cleared.');setSaveLabel('Sign in to save');dialog.close()}
  async function submitAuth(e){e.preventDefault();if(!client){msg('StudyPilot has not been configured by the site administrator yet. Please try again later.',true);return}const email=$('#authEmail').value.trim(),password=$('#authPassword').value;$('#authSubmit').disabled=true;msg(authMode==='signup'?'Creating account…':'Signing in…');try{let result;if(authMode==='signup'){const full_name=$('#authDisplayName').value.trim();result=await client.auth.signUp({email,password,options:{data:{full_name}}})}else result=await client.auth.signInWithPassword({email,password});if(result.error)throw result.error;if(authMode==='signup'&&!result.data.session){msg('Account created. Check your email to confirm your address, then return here to sign in.');return}if(result.data.user){await loadStudentData(result.data.user);if(result.data.session){msg('You are signed in. Your personal study data is connected.');dialog.close()}}}catch(err){console.error('StudyPilot authentication failed',err);msg('We could not complete sign-in. Check your details and try again.',true)}finally{$('#authSubmit').disabled=false}}
  async function forgotPassword(){if(!client){msg('Site configuration is incomplete.',true);return}const email=$('#authEmail').value.trim();if(!email){msg('Enter your email address first, then choose Forgot password.',true);return}try{const {error}=await client.auth.resetPasswordForEmail(email,{redirectTo:window.location.href.split('#')[0]});if(error)throw error;msg('If the address is registered, a password-reset email will arrive shortly.')}catch(e){console.error('StudyPilot password reset failed',e);msg('We could not request a password reset. Please try again later.',true)}}
  window.StudyPilotAuth={
    isSignedIn:()=>Boolean(currentUser),
    submitFeedback:async({category,rating,message})=>{
      if(!client||!currentUser)throw new Error('Sign in to send feedback.');
      const {error}=await client.from('studypilot_feedback').insert({user_id:currentUser.id,category,rating:rating?Number(rating):null,message});
      if(error){console.error('StudyPilot feedback submission failed',error);throw new Error('We could not send your feedback. Please try again later.')}
    },
    reportProblem:async(message)=>{
      if(!client||!currentUser)throw new Error('Sign in to send a problem report.');
      const {error}=await client.from('studypilot_support_reports').insert({user_id:currentUser.id,category:'student_report',user_message:message,diagnostic_code:'student_reported_issue',app_version:'4.0',page_name:document.querySelector('.page.active')?.id||'unknown'});
      if(error){console.error('StudyPilot support report failed',error);throw new Error('We could not send your report. Please try again later.')}
    },
    listPublishedSubjects:async(level)=>{
      if(!client||!currentUser)throw new Error('Sign in to view the official curriculum.');
      const {data,error}=await client.from('curriculum_subjects').select('id,name,level').eq('curriculum','UNEB').eq('level',level).eq('is_published',true).order('display_order').order('name');
      if(error)throw error;return data||[];
    },
    saveSelectedSubjects:async(ids,level)=>{
      if(!client||!currentUser)throw new Error('Sign in to save your subjects.');
      // A student works from one chosen level at a time. Changing selections does not
      // delete planner sessions; stable curriculum IDs reconnect the history if reselected.
      const {error:delError}=await client.from('student_subjects').delete().eq('user_id',currentUser.id);if(delError)throw delError;
      if(ids.length){const {error}=await client.from('student_subjects').upsert(ids.map(subject_id=>({user_id:currentUser.id,subject_id})),{onConflict:'user_id,subject_id'});if(error)throw error}
      const {error:profileError}=await client.from('student_academic_profiles').upsert({user_id:currentUser.id,academic_level:level,updated_at:new Date().toISOString()},{onConflict:'user_id'});if(profileError)throw profileError;
      const {data:selected,error:selError}=await client.from('student_subjects').select('subject_id').eq('user_id',currentUser.id);if(selError)throw selError;
      const allIds=(selected||[]).map(x=>x.subject_id);let subjects=[];
      if(allIds.length){const {data,error}=await client.from('curriculum_subjects').select('id,name,level').in('id',allIds);if(error)throw error;subjects=data||[]}
      const subjectIds=subjects.map(x=>x.id);let official=[];
      if(subjectIds.length){
        const {data:topics,error:te}=await client.from('curriculum_topics').select('id,subject_id,name,term').in('subject_id',subjectIds).order('display_order');if(te)throw te;
        const topicMap=new Map((topics||[]).map(t=>[t.id,t]));const topicIds=[...topicMap.keys()];let subs=[];
        if(topicIds.length){const {data,error:se}=await client.from('curriculum_subtopics').select('id,topic_id,name').in('topic_id',topicIds).order('display_order');if(se)throw se;subs=data||[]}
        const subMap=new Map(subs.map(st=>[st.id,st]));const subIds=[...subMap.keys()];let concepts=[];
        if(subIds.length){const {data,error:ce}=await client.from('curriculum_concepts').select('*').in('subtopic_id',subIds).order('display_order');if(ce)throw ce;concepts=data||[]}
        const subjectMap=new Map(subjects.map(x=>[x.id,x]));
        official=concepts.map(c=>{const st=subMap.get(c.subtopic_id),t=topicMap.get(st?.topic_id),sub=subjectMap.get(t?.subject_id);return{id:c.id,subject:sub?.name||'Other',paper:t?.term||'',topic:t?.name||'',subtopic:st?.name||'',name:c.name,description:c.description||'',type:'mixed',difficulty:c.difficulty,importance:c.importance,learnMin:c.learn_minutes,reviewMin:c.review_minutes,practiceMin:c.practice_minutes,targetReps:c.target_repetitions,targetQuestions:c.target_questions,centralCurriculum:true,academicLevel:sub?.level||level}}).filter(c=>c.name&&c.subject);
      }
      const current=window.StudyPilot.getData(),selectedNames=subjects.map(x=>x.name);
      const legacy=current.concepts.filter(c=>!c.centralCurriculum);
      const oldOfficial=current.concepts.filter(c=>c.centralCurriculum).map(c=>({...c,academicLevel:c.academicLevel||'Legacy'}));
      // Keep old official records in the private planner snapshot. Only currently selected
      // subjects are shown; reselecting a subject reconnects its stable concept IDs to history.
      const byId=new Map([...oldOfficial,...official].map(c=>[c.id,c]));
      const merged=[...legacy,...byId.values()];
      const names=[...new Set([...selectedNames,...legacy.map(c=>c.subject)])];
      const next={...current,subjects:names,concepts:merged};
      next.profile={...next.profile,level,curriculum:'UNEB',subjectOrder:[...new Set([...selectedNames,...(next.profile.subjectOrder||[])])]};
      window.StudyPilot.replaceData(next);
      await refreshNoticeboard();
      return {subjects:selectedNames,concepts:official.length};
    }
  };
  async function refreshCentralSubjectChoices(){
    const box=$('#centralSubjectChoices');if(!box)return;
    if(!currentUser){box.textContent='Sign in to choose published subjects.';return}
    const selector=$('#centralCurriculumLevel');
    const profileLevel=window.StudyPilot.getData().profile.level;
    if(selector&&selector.dataset.initialized!=='true'){if(['O Level','A Level'].includes(profileLevel))selector.value=profileLevel;selector.dataset.initialized='true'}
    const level=selector?.value||'O Level';
    try{
      const {data,error}=await client.from('curriculum_subjects').select('id,name').eq('curriculum','UNEB').eq('level',level).eq('is_published',true).order('display_order').order('name');
      if(error)throw error;
      const {data:selected,error:se}=await client.from('student_subjects').select('subject_id').eq('user_id',currentUser.id);if(se)throw se;
      const chosen=new Set((selected||[]).map(x=>x.subject_id));
      box.innerHTML=data.length?data.map(s=>`<label class="check-row"><input type="checkbox" name="centralSubject" value="${s.id}" ${chosen.has(s.id)?'checked':''}> ${String(s.name).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}</label>`).join(''):'No published subjects are available for this level yet.';
    }catch(e){console.error('StudyPilot curriculum list failed',e);box.textContent='Could not load published subjects. Please try again later.'}
  }

  const noticeEsc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  let cachedNotices=[];
  async function refreshNoticeboard(){
    const summary=$('#dashboardNoticeSummary'),list=$('#noticeboardList');if(!currentUser){if(summary)summary.innerHTML='<p class="muted">Sign in to see notices for your academic level.</p>';if(list)list.innerHTML='<div class="panel">Sign in to view notices.</div>';return}
    try{
      const {data,error}=await client.from('studypilot_notices').select('id,title,body,category,target_level,target_subject_id,published_at,created_at').eq('is_published',true).order('published_at',{ascending:false}).limit(100);
      if(error)throw error;
      const {data:reads,error:re}=await client.from('studypilot_notice_reads').select('notice_id').eq('user_id',currentUser.id);if(re)throw re;
      const readSet=new Set((reads||[]).map(x=>x.notice_id));
      cachedNotices=(data||[]).map(n=>({...n,isRead:readSet.has(n.id)}));
      const unread=cachedNotices.filter(n=>!n.isRead).length,badge=$('#noticeUnreadBadge');
      if(badge){badge.textContent=unread>9?'9+':String(unread);badge.hidden=unread===0}
      const html=(items,compact=false)=>items.length?items.map(n=>`<article class="notice-card ${n.isRead?'read':'unread'}"><div class="notice-card-head"><strong>${noticeEsc(n.title)}</strong><span class="notice-category">${n.isRead?'':'New · '}${noticeEsc((n.category||'announcement').replace(/_/g,' '))}</span></div><p>${noticeEsc(n.body)}</p><div class="notice-card-foot"><small>${n.published_at?new Date(n.published_at).toLocaleString():new Date(n.created_at).toLocaleString()}</small>${n.isRead?'<span class="muted">Read</span>':`<button class="mini-btn" data-read-notice="${n.id}">Mark as read</button>`}</div></article>`).join(''):'<div class="empty-state">There are no notices for your selected academic level and subjects yet.</div>';
      if(summary)summary.innerHTML=html(cachedNotices.slice(0,3),true);
      if(list)list.innerHTML=html(cachedNotices);
      [summary,list].filter(Boolean).forEach(root=>root.querySelectorAll('[data-read-notice]').forEach(btn=>btn.addEventListener('click',()=>markNoticeRead(btn.dataset.readNotice))));
    }catch(e){console.error('StudyPilot Noticeboard could not load',e);if(summary)summary.textContent='Notices could not be loaded. Please try again.';if(list)list.textContent='Notices could not be loaded. Please try again.'}
  }
  async function markNoticeRead(id){
    if(!currentUser)return;
    try{const {error}=await client.from('studypilot_notice_reads').upsert({notice_id:id,user_id:currentUser.id},{onConflict:'notice_id,user_id',ignoreDuplicates:true});if(error)throw error;await refreshNoticeboard()}
    catch(e){console.error('Could not mark notice as read',e)}
  }
  async function refreshSuggestionSubjects(){
    const select=$('#suggestionSubject');if(!select)return;if(!currentUser){select.innerHTML='<option value="">Sign in to load your subjects</option>';return}
    const level=$('#suggestionLevel')?.value||'O Level';select.innerHTML='<option value="">Loading subjects…</option>';
    try{
      const {data:chosen,error}=await client.from('student_subjects').select('subject_id').eq('user_id',currentUser.id);if(error)throw error;
      const ids=(chosen||[]).map(x=>x.subject_id);let subjects=[];
      if(ids.length){const {data,error:se}=await client.from('curriculum_subjects').select('id,name,level').in('id',ids).eq('level',level);if(se)throw se;subjects=data||[]}
      select.innerHTML='<option value="">Choose one of your selected subjects</option>'+subjects.map(x=>`<option value="${noticeEsc(x.name)}">${noticeEsc(x.name)}</option>`).join('');
      if(!subjects.length)select.innerHTML='<option value="">No selected subjects at this level</option>';
    }catch(e){select.innerHTML='<option value="">Could not load subjects</option>'}
  }
  async function loadMySuggestions(){
    const box=$('#mySuggestions');if(!box)return;if(!currentUser){box.textContent='Sign in to view your suggestions.';return}
    try{const {data,error}=await client.from('studypilot_concept_suggestions').select('academic_level,subject_name,topic_name,subtopic_name,concept_name,status,created_at,admin_notes').eq('user_id',currentUser.id).order('created_at',{ascending:false}).limit(50);if(error)throw error;
      box.innerHTML=data.length?data.map(x=>`<article class="notice-card"><div class="notice-card-head"><strong>${noticeEsc(x.concept_name)}</strong><span class="notice-category">${noticeEsc(x.status)}</span></div><p>${noticeEsc(x.academic_level)} · ${noticeEsc(x.subject_name)} · ${noticeEsc(x.topic_name)}${x.subtopic_name?' · '+noticeEsc(x.subtopic_name):''}</p>${x.admin_notes?`<small>${noticeEsc(x.admin_notes)}</small>`:''}</article>`).join(''):'You have not submitted any concept suggestions yet.';
    }catch(e){box.textContent='Could not load your suggestions.'}
  }

  async function loadStudentResources(){
    const box=$('#studentResourcesList');if(!box)return;if(!currentUser){box.innerHTML='<div class="panel">Sign in to browse learning resources.</div>';return}
    box.textContent='Loading learning resources…';
    try{
      const {data,error}=await client.from('resources').select('id,title,category,description,file_url,author,level,doi,created_at').order('created_at',{ascending:false}).limit(300);if(error)throw error;
      box.innerHTML=data.length?data.map(r=>`<article class="notice-card"><div class="notice-card-head"><strong>${noticeEsc(r.title)}</strong><span class="notice-category">${noticeEsc(r.category||'Resource')}</span></div><p>${noticeEsc(r.description||'No description provided.')}</p><div class="notice-card-foot"><span>${noticeEsc(r.level||'All levels')}${r.author?' · '+noticeEsc(r.author):''}</span>${/^https?:\/\//i.test(r.file_url||'')?`<a href="${noticeEsc(r.file_url)}" target="_blank" rel="noopener noreferrer">Open resource ↗</a>`:'<span class="muted">No safe link available</span>'}</div></article>`).join(''):'<div class="empty-state">No learning resources have been added yet.</div>';
    }catch(e){console.error('Could not load resources',e);box.textContent='Learning resources could not be loaded. Please try again later.'}
  }
  async function submitConceptSuggestion(e){
    e.preventDefault();if(!currentUser){$('#suggestionMessage').textContent='Sign in before submitting a suggestion.';return}
    const btn=e.currentTarget.querySelector('button[type="submit"]'),level=$('#suggestionLevel').value,subject=$('#suggestionSubject').value;
    if(!subject){$('#suggestionMessage').textContent='Choose one of your selected subjects first.';return}
    btn.disabled=true;$('#suggestionMessage').textContent='Submitting suggestion…';
    try{
      const profile=await client.from('student_academic_profiles').upsert({user_id:currentUser.id,academic_level:level,updated_at:new Date().toISOString()},{onConflict:'user_id'});if(profile.error)throw profile.error;
      const {error}=await client.from('studypilot_concept_suggestions').insert({user_id:currentUser.id,academic_level:level,subject_name:subject,topic_name:$('#suggestionTopic').value.trim(),subtopic_name:$('#suggestionSubtopic').value.trim()||null,concept_name:$('#suggestionConcept').value.trim(),description:$('#suggestionDescription').value.trim()||null});if(error)throw error;
      e.currentTarget.reset();$('#suggestionLevel').value=level;await refreshSuggestionSubjects();$('#suggestionMessage').textContent='Suggestion submitted. It will appear in the official curriculum only after administrator review.';await loadMySuggestions();
    }catch(err){$('#suggestionMessage').textContent='Could not submit suggestion. Please try again.';console.error(err)}finally{btn.disabled=false}
  }
  function bind(){
    $('#centralCurriculumLevel')?.addEventListener('change',refreshCentralSubjectChoices);
    $('#suggestionLevel')?.addEventListener('change',refreshSuggestionSubjects);
    $('#conceptSuggestionForm')?.addEventListener('submit',submitConceptSuggestion);
    document.querySelectorAll('[data-page]').forEach(b=>b.addEventListener('click',()=>{if(b.dataset.page==='noticeboard')refreshNoticeboard();if(b.dataset.page==='suggest'){refreshSuggestionSubjects();loadMySuggestions()}if(b.dataset.page==='resources')loadStudentResources()}));
    $('#centralCurriculumForm')?.addEventListener('submit',async e=>{e.preventDefault();const btn=e.currentTarget.querySelector('button[type="submit"]'),msgEl=$('#centralCurriculumMessage');if(!currentUser){msgEl.textContent='Sign in before selecting subjects.';return}const ids=Array.from(e.currentTarget.querySelectorAll('input[name="centralSubject"]:checked')).map(x=>x.value);btn.disabled=true;msgEl.textContent='Saving your subjects and loading the curriculum…';try{const level=$('#centralCurriculumLevel').value,result=await window.StudyPilotAuth.saveSelectedSubjects(ids,level);msgEl.textContent=`Loaded ${result.concepts} official concepts across ${result.subjects.length} selected subjects. Your existing study history was preserved.`}catch(err){console.error('StudyPilot curriculum load failed',err);msgEl.textContent='We could not load the curriculum. Please try again later.'}finally{btn.disabled=false}});
    $('#accountTrigger').addEventListener('click',showDialog);$('#openAccountSettings').addEventListener('click',showDialog);$('#closeAccount').addEventListener('click',()=>dialog.close());$('#accountForm').addEventListener('submit',submitAuth);$('#authToggleMode').addEventListener('click',()=>setMode(authMode==='signup'?'signin':'signup'));$('#authForgotPassword').addEventListener('click',forgotPassword);$('#authSignOut').addEventListener('click',signOut);
    $('#studentFeedbackForm')?.addEventListener('submit',async e=>{e.preventDefault();const f=e.currentTarget,btn=f.querySelector('button[type="submit"]'),d=new FormData(f);btn.disabled=true;try{await window.StudyPilotAuth.submitFeedback({category:d.get('category'),rating:d.get('rating'),message:d.get('message').trim()});f.reset();$('#feedbackFormMessage').textContent='Thank you. Your feedback has been sent.'}catch(err){$('#feedbackFormMessage').textContent=err.message}finally{btn.disabled=false}});
    $('#studentSupportForm')?.addEventListener('submit',async e=>{e.preventDefault();const f=e.currentTarget,btn=f.querySelector('button[type="submit"]'),message=new FormData(f).get('message').trim();btn.disabled=true;try{await window.StudyPilotAuth.reportProblem(message);f.reset();$('#supportFormMessage').textContent='Your problem report has been sent. Thank you.'}catch(err){$('#supportFormMessage').textContent=err.message}finally{btn.disabled=false}});
    $('#goToProfile').addEventListener('click',()=>{dialog.close();window.StudyPilot.go('settings');document.querySelector('#profileForm input[name="name"]').focus()});
    window.addEventListener('studypilot:data-saved',e=>{renderAccount();if(!isApplyingCloud)scheduleSync(e.detail.data)});
  }
  bind();
  if(configured&&window.supabase?.createClient){try{client=window.supabase.createClient(cfg.SUPABASE_URL,cfg.SUPABASE_PUBLIC_KEY);client.auth.getSession().then(({data,error})=>{if(error)throw error;if(data.session?.user)loadStudentData(data.session.user);else renderAccount()}).catch(e=>{console.error(e);msg('We could not check your account session. Please refresh and try again.',true)});client.auth.onAuthStateChange((event)=>{if(event==='SIGNED_OUT'){clearTimeout(syncTimer);currentUser=null;isApplyingCloud=true;window.StudyPilot.replaceData(window.StudyPilot.freshData());isApplyingCloud=false;renderAccount();refreshNoticeboard();loadMySuggestions();loadStudentResources();setSaveLabel('Sign in to save')}})}catch(e){console.error(e);msg('Could not initialize the cloud connection.',true)}}else{setSaveLabel('Cloud not configured',true);$('#settingsAccountStatus').textContent='The site administrator needs to add the Supabase URL and public key in config.js.';renderAccount()}
})();
