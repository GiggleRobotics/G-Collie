import React from'react';
export default function CollieBrand({hero=false,className=''}:{hero?:boolean;className?:string}){return <img className={(hero?'collie-hero':'collie-mark')+' '+className} src={hero?'/brand/collie-companion-v2.png':'/brand/collie-mark-v2.png'} alt={hero?'戴着 G 项圈的边牧伙伴':'G-Collie 边牧标识'} draggable={false}/>}
