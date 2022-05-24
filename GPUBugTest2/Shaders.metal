//
//  Shaders.metal
//  Desync
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float4 position [[ attribute(0) ]];
    float4 color [[ attribute(1) ]];
};

struct VertexOut {
    float4 position [[ position ]];
    float4 color;
};

fragment half4 fragment_color_shader(const VertexOut vertexIn [[ stage_in ]]) {
    half4 tmp = half4(vertexIn.color);
    for (int k = 0; k < 300; k++) {
        tmp[0] += half(k);
    }
    return tmp;
}

vertex VertexOut vertex_shader(const VertexIn vertexIn [[ stage_in ]]) {
    VertexOut vertexOut;
    vertexOut.position = vertexIn.position;
    vertexOut.color = vertexIn.color;
    return vertexOut;
}
