import {setGlobalOptions} from "firebase-functions/v2";
import {REGION} from "./lib/options";

setGlobalOptions({region: REGION, maxInstances: 20});

export {onUserWritten} from "./triggers/onUserWritten";
export {onCallCreated} from "./triggers/onCallCreated";
export {onCallStatusChanged} from "./triggers/onCallStatusChanged";
export {sweepStaleCalls} from "./triggers/sweepStaleCalls";
export {resolveVoipUsers} from "./callable/resolveVoipUsers";
