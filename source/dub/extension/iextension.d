/// Base class for extension
module dub.extension.iextension;

import dub.internal.sdlang.ast;

/// Base interface for our extension
interface IExtension
{
    void readConfig (Tag sdl);
    void preBuild ();
    //void generateTargets(GeneratorSettings settings, in TargetInfo[string] targets);
    //void performPostGenerateActions(GeneratorSettings settings, in TargetInfo[string] targets)
}
