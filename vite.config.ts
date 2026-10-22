import {defineConfig} from 'vite';
export default defineConfig({server:{fs:{strict:true,allow:[process.cwd()],deny:['**/.data/**','**/.env*','**/.git/**']},host:'0.0.0.0',allowedHosts:['localhost','127.0.0.1','192.168.1.196']},build:{outDir:'dist'}});
