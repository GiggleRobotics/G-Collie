/** Read-only coalescing and cooldown. No writes or automatic retries. */
export class ReadBudget {
 private pending=new Map<string,Promise<any>>();private failures=new Map<string,number>();private until=new Map<string,number>();
 constructor(private now=()=>Date.now()){}
 remaining(key:string){return Math.max(0,(this.until.get(key)||0)-this.now())}
 failed(key:string,retryAfter?:string|null){const n=Math.min(6,(this.failures.get(key)||0)+1);this.failures.set(key,n);let wait=Math.min(60000,1000*2**n)+Math.random()*500;if(retryAfter){const seconds=Number(retryAfter);const parsed=Number.isFinite(seconds)?seconds*1000:Date.parse(retryAfter)-this.now();if(Number.isFinite(parsed)&&parsed>=0)wait=Math.min(3600000,parsed)}this.until.set(key,this.now()+wait)}
 run<T>(key:string,read:()=>Promise<T>):Promise<T>{const active=this.pending.get(key);if(active)return active;if(this.remaining(key)>0)return Promise.reject(Error('请求暂时受限，请稍后重试'));const value=Promise.resolve().then(read).then(v=>{this.failures.delete(key);this.until.delete(key);return v}).finally(()=>{this.pending.delete(key)});this.pending.set(key,value);return value}
}
