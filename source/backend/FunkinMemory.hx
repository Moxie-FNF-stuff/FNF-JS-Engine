package backend;

import flixel.FlxG;
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import openfl.Assets;
import openfl.media.Sound;

using StringTools;

/**
 * Owns all texture/sound caching. Paths resolves file paths and asks this class for the assets.
 */
@:nullSafety
class FunkinMemory
{
  static var permanentTextures:Map<String, FlxGraphic> = [];
  static var currentTextures:Map<String, FlxGraphic> = [];
  static var previousTextures:Map<String, FlxGraphic> = [];

  static var permanentSounds:Map<String, Sound> = [];
  static var currentSounds:Map<String, Sound> = [];
  static var previousSounds:Map<String, Sound> = [];

  /** Keys that are never purged, even if they get loaded later. (Old Paths.dumpExclusions) */
  static var reserved:Array<String> = [
    'assets/music/freakyMenu.${Paths.SOUND_EXT}',
    'assets/shared/music/breakfast.${Paths.SOUND_EXT}',
    'assets/shared/music/tea-time.${Paths.SOUND_EXT}',
  ];

  /** Preloads things that are always needed. Call once after Paths is usable. */
  public static function initialCache():Void
  {
    for (img in ['alphabet', 'healthBar', 'menuDesat', 'menuBG'])
      permanentCacheTexture(img);

    for (snd in ['cancelMenu', 'confirmMenu', 'scrollMenu'])
      permanentCacheSound(snd);
	  
    for (snd in ['missnote1', 'missnote2', 'missnote3'])
      permanentCacheSound(snd, 'shared');

    permanentCacheMusic('freakyMenu');
    permanentCacheMusic('freakyMenu-' + ClientPrefs.daMenuMusic);
  }

  ///// STORAGE (called by Paths) /////

  public static function getTexture(key:String):Null<FlxGraphic>
  {
    var g:Null<FlxGraphic> = permanentTextures.get(key);
    if (g != null) return g;

    g = currentTextures.get(key);
    if (g != null) return g;

    g = previousTextures.get(key);
    if (g != null)
    {
      // Still wanted by the new state, so rescue it from the purge.
      previousTextures.remove(key);
      currentTextures.set(key, g);
    }
    return g;
  }

  public static function storeTexture(key:String, graphic:FlxGraphic):Void
  {
    if (graphic == null) return;
    graphic.persist = true;
    if (reserved.contains(key)) permanentTextures.set(key, graphic);
    else currentTextures.set(key, graphic);
  }

  public static function getSound(key:String):Null<Sound>
  {
    var s:Null<Sound> = permanentSounds.get(key);
    if (s != null) return s;

    s = currentSounds.get(key);
    if (s != null) return s;

    s = previousSounds.get(key);
    if (s != null)
    {
      previousSounds.remove(key);
      currentSounds.set(key, s);
    }
    return s;
  }

  public static function storeSound(key:String, sound:Sound):Void
  {
    if (sound == null) return;
    if (reserved.contains(key)) permanentSounds.set(key, sound);
    else currentSounds.set(key, sound);
  }

  /** Protects a key from purging (old Paths.excludeAsset). Promotes it if already cached. */
  public static function exclude(key:String):Void
  {
    if (!reserved.contains(key)) reserved.push(key);

    var g:Null<FlxGraphic> = currentTextures.get(key);
    if (g == null) g = previousTextures.get(key);
    if (g != null)
    {
      currentTextures.remove(key);
      previousTextures.remove(key);
      permanentTextures.set(key, g);
    }

    var s:Null<Sound> = currentSounds.get(key);
    if (s == null) s = previousSounds.get(key);
    if (s != null)
    {
      currentSounds.remove(key);
      previousSounds.remove(key);
      permanentSounds.set(key, s);
    }
  }

  public static function isTextureCached(key:String):Bool
    return permanentTextures.exists(key) || currentTextures.exists(key) || previousTextures.exists(key);

  public static function isSoundCached(key:String):Bool
    return permanentSounds.exists(key) || currentSounds.exists(key) || previousSounds.exists(key);

  ///// PURGING /////

  /** Phase 1 (old clearStoredMemory): everything non-permanent becomes "previous". */
  public static function preparePurge():Void
  {
    purgeUnused(); // Anything still in previous was never reused, so it's dead.

    previousTextures = currentTextures;
    currentTextures = [];
    previousSounds = currentSounds;
    currentSounds = [];

    // Drop graphics that never went through Paths (makeGraphic, direct loadGraphic, etc).
    @:privateAccess
    for (key in keysOf(FlxG.bitmap._cache))
    {
      if (isTextureCached(key)) continue;
      var obj:Null<FlxGraphic> = FlxG.bitmap._cache.get(key);
      if (obj != null) disposeTexture(key, obj);
    }

    #if !html5 Assets.cache.clear('songs'); #end
  }

  /** Phase 2 (old clearUnusedMemory): destroy whatever the new state didn't ask for. */
  public static function purgeUnused():Void
  {
    for (key in keysOf(previousTextures))
    {
      var g:Null<FlxGraphic> = previousTextures.get(key);
      previousTextures.remove(key);
      if (g != null) disposeTexture(key, g);
    }

    for (key in keysOf(previousSounds))
    {
      previousSounds.remove(key);
      Assets.cache.clear(key);
    }
  }

  static function disposeTexture(key:String, graphic:FlxGraphic):Void
  {
    @:privateAccess FlxG.bitmap._cache.remove(key);
    Assets.cache.removeBitmapData(key);
    graphic.persist = false;
    graphic.destroy();
  }

  // Snapshot keys so removing while looping is safe.
  static inline function keysOf<T>(map:Map<String, T>):Array<String>
    return [for (k in map.keys()) k];

  ///// PRELOADING /////

  public static function cacheTexture(key:String, ?library:String):Void
  {
    var graphic:FlxGraphic = Paths.image(key, library);
    if (graphic == null) FlxG.log.warn('Failed to cache graphic: $key');
    else forceRender(graphic);
  }

  public static function permanentCacheTexture(key:String, ?library:String):Void
  {
    var graphic:FlxGraphic = Paths.image(key, library);
    if (graphic == null)
    {
      FlxG.log.warn('Failed to cache graphic: $key');
      return;
    }
    exclude(graphic.key);
    forceRender(graphic);
    log('Permanently cached graphic $key');
  }

  public static function cacheSound(key:String, ?library:String):Void
    Paths.sound(key, library);

  public static function permanentCacheSound(key:String, ?library:String):Void
    protectSound(key, Paths.sound(key, library));

  public static function permanentCacheMusic(key:String, ?library:String):Void
    protectSound(key, Paths.music(key, library));

  static function protectSound(key:String, sound:Sound):Void
  {
    if (sound == null) return;
    for (path in keysOf(currentSounds))
    {
      if (currentSounds.get(path) == sound)
      {
        exclude(path);
        log('Permanently cached sound $key');
        return;
      }
    }
  }

  static function forceRender(graphic:FlxGraphic):Void
  {
    if (graphic == null || graphic.bitmap == null) return;

    var sprite = new FlxSprite();
    sprite.loadGraphic(graphic);
    sprite.draw();
    graphic.bitmap.getTexture(FlxG.stage.context3D);
    sprite.destroy();
  }

  static function log(message:String):Void
    trace('MEMORY: $message');
}