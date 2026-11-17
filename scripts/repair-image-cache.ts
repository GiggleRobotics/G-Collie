/** Manual rerun of the same safe migration used at service startup. */
import {resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {homedir} from 'node:os';
import {repairImageCaches} from '../server/image-cache.js';
export {repairImageCaches};
if(process.argv[1]&&import.meta.url===pathToFileURL(resolve(process.argv[1])).href){
 const result=await repairImageCaches(process.env.GCOLLIE_DATA_DIR||join(homedir(),'.local/share/g-collie'));
 console.log(JSON.stringify(result));if(result.errors.length)process.exitCode=1;
}
