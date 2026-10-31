public enum PlasmaShader{
    public static let source = #"""
    #include <metal_stdlib>
    using namespace metal;
    struct Uniforms{float4 viewport,hot,deep,animation,edge,dynamics,options;float4 spectrum[4];};
    vertex float4 rimVertex(uint id [[vertex_id]]){float2 p[3]={float2(-1,-1),float2(3,-1),float2(-1,3)};return float4(p[id],0,1);}
    float roundedDistance(float2 p,float2 size,float radius){float2 q=abs(p)-size*0.5f+radius;return length(max(q,0.0f))+min(max(q.x,q.y),0.0f)-radius;}
    fragment half4 rimFragment(float4 pixel [[position]],constant Uniforms &u [[buffer(0)]]){
        if(u.viewport.w<0.5f)return half4(0);
        float2 size=u.viewport.xy,p=pixel.xy/max(1.0f,u.viewport.z)-size*0.5f;
        float inside=-roundedDistance(p,size,u.animation.z);
        if(u.edge.x>0)inside=min(inside,roundedDistance(p-float2(0,(u.edge.y-size.y)*0.5f),u.edge.xy,8.0f));
        if(inside<0)return half4(0);
        float along;
        if(abs(p.y)/size.y>abs(p.x)/size.x)along=p.y<0 ? p.x+size.x*0.5f : size.x+size.y+size.x*0.5f-p.x;
        else along=p.x>0 ? size.x+p.y+size.y*0.5f : size.x*2+size.y+size.y*0.5f-p.y;
        float s=along/(2*(size.x+size.y)),time=u.animation.x,phase=u.animation.y;
        float bass=u.dynamics.x,high=u.dynamics.z,bounce=max(0.0f,u.dynamics.w)*u.options.y;
        float thickness=max(1.0f,u.edge.w*7.0f),glow=min(u.hot.w,min(size.x,size.y)*0.16f);
        float3 hot=u.hot.xyz,deep=u.deep.xyz,rgb=hot;
        float a=0;
        int style=int(u.options.x);
        if(style==1){
            float wave=0.5f+0.5f*sin(s*31.4159f-time*0.8f+sin(s*12.566f+time*0.4f));
            float width=thickness*(0.45f+wave*1.3f)+bass*8+bounce*12;
            rgb=mix(hot,deep,0.5f+0.5f*sin(s*18.85f-time*0.45f));
            a=(1-smoothstep(width,width+max(2.0f,glow*0.5f),inside))*(0.38f+wave*0.62f);
        }else if(style==2){
            float distance=fract(s-phase-time*0.055f);
            float tail=pow(1-distance,18.0f),head=exp(-distance*distance*42000.0f);
            float width=thickness*0.6f+tail*5+bounce*5;
            rgb=mix(deep,hot,tail);rgb=mix(rgb,float3(1),head*0.85f);
            a=tail*(1-smoothstep(width,width+max(2.0f,glow*0.32f),inside));
        }else if(style==3){
            float wavePosition=atan2(p.y,p.x)/6.2831853f;
            float swell=sin(wavePosition*37.6991f-time*1.8f-phase*6.2832f);
            float ripple=sin(wavePosition*75.3982f+time*1.1f);
            float width=max(1.5f,thickness+5+(3+u.dynamics.y*7)*swell+high*3*ripple+bounce*10);
            float crest=exp(-pow((inside-width)/1.4f,2.0f));
            float body=(1-smoothstep(width-1,width+1,inside))*0.65f;
            a=max(body,crest);
            if(glow>0)a=max(a,0.22f*exp(-max(0.0f,inside-width)/max(1.0f,glow*0.22f)));
            rgb=mix(deep,hot,0.5f+0.5f*sin(wavePosition*12.5664f-time*0.35f));
            rgb=mix(rgb,float3(1),crest*0.3f);
        }else if(style==4){
            int bar=min(63,int(fract(s)*64)),bin=bar%16;
            float energy=u.spectrum[bin/4][bin%4];
            float cell=fract(s*64),gap=smoothstep(0.08f,0.18f,cell)*(1-smoothstep(0.76f,0.86f,cell));
            float width=2+energy*(thickness+22)+bounce*6;
            rgb=mix(deep,hot,energy);
            a=gap*(1-smoothstep(width-0.5f,width+0.7f,inside));
            if(glow>0)a=max(a,gap*0.12f*exp(-abs(inside-width)/max(0.5f,min(3.0f,glow*0.05f))));
        }else if(style==8){
            float first=3+thickness*0.35f+sin(s*25.13f-time)*2+bounce*6;
            float second=first+8+sin(s*18.85f+time*0.7f)*2;
            float third=second+8;
            float l1=exp(-pow((inside-first)/(1.0f+min(1.2f,glow*0.018f)),2.0f));
            float l2=exp(-pow((inside-second)/(0.85f+min(0.9f,glow*0.014f)),2.0f))*0.7f;
            float l3=exp(-pow((inside-third)/(0.5f+min(0.7f,glow*0.01f)),2.0f))*0.28f;
            a=max(l1,max(l2,l3));rgb=mix(hot,deep,clamp((inside-first)/18,0.0f,1.0f));
        }else{
            float width=0.9f+min(2.0f,thickness*0.07f+bass*0.45f+bounce*0.15f);
            a=1-smoothstep(width,width+0.8f,inside);rgb=mix(hot,deep,0.5f);
            if(glow>0)a=max(a,0.15f*exp(-max(inside-width,0.0f)/max(0.4f,min(2.0f,glow*0.025f))));
        }
        if(inside>min(size.x,size.y)*0.23f)a=0;
        rgb=clamp(rgb*(1+bass*0.16f+high*0.05f),0.0f,1.0f);
        a=clamp(a,0.0f,1.0f);
        return half4(half3(rgb)*half(a),half(a));
    }
    """#
}
