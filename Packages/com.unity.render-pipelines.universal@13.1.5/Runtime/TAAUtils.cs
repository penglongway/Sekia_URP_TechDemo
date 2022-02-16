namespace UnityEngine.Rendering.Universal
{
    internal class TAAUtils
    {
        private const int k_SampleCount = 8;

        public static int sampleIndex { get; private set; }

        public static float HaltonSeq(int index, int radix)
        {
            float result = 0f;
            float fraction = 1f / (float)radix;

            while (index > 0)
            {
                result += (float)(index % radix) * fraction;

                index /= radix;
                fraction /= (float)radix;
            }

            return result;

            //结果1X：1%2 *1/2                                     = 1/2 
            //结果2X：2%2 *1/2 + 1%2 *1/4                          = 1/4
            //结果3X：3%2 *1/2 + 1%2 *1/4                          = 3/4
            //结果4X：4%2 *1/2 + 2%2 *1/4 + 1%2 * 1/8              = 1/8
            //结果5X：5%2 *1/2 + 2%2 *1/4 + 1%2 * 1/8              = 5/8
            //结果6X：6%2 *1/2 + 3%2 *1/4 + 1%2 * 1/8              = 3/8
            //结果7X：7%2 *1/2 + 3%2 *1/4 + 1%2 * 1/8              = 7/8
            //结果8X：8%2 *1/2 + 4%2 *1/4 + 2%2 * 1/8 + 1%2 * 1/16 = 1/16

            //结果1Y：1%3 *1/3            = 1/3
            //结果2Y：2%3 *1/3            = 2/3
            //结果3Y：3%3 *1/3 + 1%3 *1/9 = 1/9
            //结果4Y：4%3 *1/3 + 1%3 *1/9 = 4/9
            //结果5Y：5%3 *1/3 + 1%3 *1/9 = 7/9
            //结果6Y：6%3 *1/3 + 2%3 *1/9 = 2/9
            //结果7Y：7%3 *1/3 + 2%3 *1/9 = 5/9
            //结果8Y：8%3 *1/3 + 2%3 *1/9 = 8/9
        }

        public static Vector2 GenerateRandomOffset()
        {
            //低差异采样序列Halton 转化为-0.5-0.5范围内的偏移
            //halton序列的index0与其他值有明显差异 这里回避index0 使用index1-8
            var offset = new Vector2(
                HaltonSeq((sampleIndex & 1023) + 1, 2) - 0.5f,
                HaltonSeq((sampleIndex & 1023) + 1, 3) - 0.5f
            );

            if (++sampleIndex >= k_SampleCount)
                sampleIndex = 0;

            return offset;
        }

        public static void GetJitteredPerspectiveProjectionMatrix(Camera camera, out Vector4 jitterPixels, out Matrix4x4 jitteredMatrix)
        {
            //moriya苏蛙可 https://zhuanlan.zhihu.com/p/64993622
            //https://zhuanlan.zhihu.com/p/297689954
            //https://zhuanlan.zhihu.com/p/20197323
            //https://zhuanlan.zhihu.com/p/463794038
            //https://zhuanlan.zhihu.com/p/425233743
            jitterPixels.z = sampleIndex;
            jitterPixels.w = k_SampleCount;
            var v = GenerateRandomOffset();
            jitterPixels.x = v.x;
            jitterPixels.y = v.y;
            var offset = new Vector2(
                jitterPixels.x / camera.pixelWidth, //除以像素宽度：得到单个像素抖动的距离 => 屏幕空间
                jitterPixels.y / camera.pixelHeight
            );
            jitteredMatrix = camera.projectionMatrix; //Unity矩阵是竖着排列的 修改第1列第3个和第二列第三个 
            jitteredMatrix.m02 += offset.x * 2; //乘以2：屏幕空间的偏移 => NDC空间的偏移
            jitteredMatrix.m12 += offset.y * 2; //m02和m12：NDC空间的偏移 * 观察空间Z => 抵消齐次去除
        }
    }
}
