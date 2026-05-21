export const FLOCK_VALIDATOR_SOURCE = `
function (newDoc, oldDoc, userCtx, secObj) {
  function reject(reason) { throw({ forbidden: reason }); }
  function unauthorized(reason) { throw({ unauthorized: reason }); }

  if (!userCtx || !userCtx.name) {
    unauthorized('login required');
  }

  var isAdmin = false;
  if (userCtx.roles) {
    for (var i = 0; i < userCtx.roles.length; i++) {
      if (userCtx.roles[i] === '_admin') { isAdmin = true; break; }
    }
  }

  if (newDoc._id && newDoc._id.indexOf('_design/') === 0) {
    if (!isAdmin) reject('design docs are admin-only');
    return;
  }

  if (newDoc._id === 'flock:meta') {
    if (!isAdmin) reject('flock:meta is admin-only');
    return;
  }

  // Server admin bypass — admins are the server's own credentials, used by
  // the auth server for provisioning and recovery. They don't need to satisfy
  // member-level integrity checks.
  if (isAdmin) return;

  var flockMeta = (secObj && secObj.flock) || null;

  if (flockMeta && flockMeta.billingStatus && flockMeta.billingStatus !== 'active') {
    reject('flock billing not active (' + flockMeta.billingStatus + ')');
  }

  if (newDoc._deleted) {
    if (flockMeta && flockMeta.billingOwner) {
      var del = oldDoc || newDoc;
      var deleteOwnerOnly = false;
      if (del.type === 'trip') deleteOwnerOnly = true;
      if (typeof del._id === 'string' && del._id.indexOf('void::trip::') === 0) deleteOwnerOnly = true;
      if (deleteOwnerOnly && userCtx.name !== flockMeta.billingOwner) {
        reject('only the billing owner can delete trip docs');
      }
    }
    return;
  }

  if (!newDoc.type || typeof newDoc.type !== 'string') {
    reject('missing type');
  }
  var allowedTypes = ['expense', 'trip', 'amend', 'void', 'flock', 'userFlocks'];
  var typeOk = false;
  for (var t = 0; t < allowedTypes.length; t++) {
    if (allowedTypes[t] === newDoc.type) { typeOk = true; break; }
  }
  if (!typeOk) {
    reject('unknown type: ' + newDoc.type);
  }
  if (!newDoc.createdBy || typeof newDoc.createdBy !== 'string') {
    reject('missing createdBy');
  }
  if (newDoc.createdBy !== userCtx.name) {
    reject('createdBy must match userCtx.name');
  }
  if (typeof newDoc._id !== 'string' || newDoc._id.length === 0) {
    reject('missing _id');
  }
  if (newDoc._id.indexOf('\\u0000') !== -1) {
    reject('malformed _id');
  }
  if (newDoc._id.indexOf('..') !== -1 || newDoc._id.indexOf('/') !== -1) {
    reject('malformed _id');
  }

  if (flockMeta && flockMeta.billingOwner) {
    var ownerOnly = false;
    if (newDoc.type === 'trip') ownerOnly = true;
    if (newDoc._id.indexOf('void::trip::') === 0) ownerOnly = true;
    if (ownerOnly && userCtx.name !== flockMeta.billingOwner) {
      reject('only the billing owner can write trip docs');
    }
  }
}
`.trim()

export const FLOCK_DESIGN_DOC_ID = '_design/flock_validator'

export function buildFlockDesignDoc(rev) {
  const doc = {
    _id: FLOCK_DESIGN_DOC_ID,
    language: 'javascript',
    validate_doc_update: FLOCK_VALIDATOR_SOURCE,
  }
  if (rev) doc._rev = rev
  return doc
}
