import React from 'react';
export default function AgentIcon({agent}:{agent:string}){return <img className="agent-logo" src={agent==='Codex'?'/icons/codex.svg':'/icons/hermes.png'} alt={`${agent} 图标`} width="32" height="32"/>}
