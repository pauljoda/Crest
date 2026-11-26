<script lang="ts">
  import lightIcon from "../../../../../CrestShared/Resources/AppIconPreviews.xcassets/CrestDockLight.imageset/icon.png";
  import darkIcon from "../../../../../CrestShared/Resources/AppIconPreviews.xcassets/CrestDockDark.imageset/icon.png";

  let { size }: { size: number } = $props();
</script>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset={darkIcon} />
  <img src={lightIcon} width={size} height={size} alt="" />
</picture>

<style>
  picture, img { display: block; flex: none; }
</style>
