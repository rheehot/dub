import dub.extension.iextension;
import dub.internal.sdlang.ast;

class WriteConfigExt : IExtension
{
    string module_;
    string file;

    override void readConfig (Tag sdl)
    {
        assert(sdl);
        this.module_ = "version";
        this.file = "version_.d";
    }

    override void preBuild ()
    {
        import std.file;
        write(this.file, q{
                module version_;
                string getVersion () { return "1.4.5"; }
            });
    }
}
