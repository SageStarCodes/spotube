import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:spotify/spotify.dart';
import 'package:spotube/components/shared/dialogs/select_device_dialog.dart';
import 'package:spotube/components/shared/playbutton_card.dart';
import 'package:spotube/extensions/artist_simple.dart';
import 'package:spotube/extensions/context.dart';
import 'package:spotube/extensions/image.dart';
import 'package:spotube/extensions/track.dart';
import 'package:spotube/models/connect/connect.dart';
import 'package:spotube/provider/connect/connect.dart';
import 'package:spotube/provider/proxy_playlist/proxy_playlist_provider.dart';
import 'package:spotube/provider/spotify/spotify.dart';
import 'package:spotube/services/audio_player/audio_player.dart';
import 'package:spotube/utils/service_utils.dart';

extension FormattedAlbumType on AlbumType {
  String get formatted => name.replaceFirst(name[0], name[0].toUpperCase());
}

class AlbumCard extends HookConsumerWidget {
  final AlbumSimple album;
  const AlbumCard(
    this.album, {
    super.key,
  });

  @override
  Widget build(BuildContext context, ref) {
    final playlist = ref.watch(proxyPlaylistProvider);
    final playing =
        useStream(audioPlayer.playingStream).data ?? audioPlayer.isPlaying;
    final playlistNotifier = ref.watch(proxyPlaylistProvider.notifier);

    bool isPlaylistPlaying = useMemoized(
      () => playlist.containsCollection(album.id!),
      [playlist, album.id],
    );

    final updating = useState(false);

    final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);

    Future<List<Track>> fetchAllTrack() async {
      if (album.tracks != null && album.tracks!.isNotEmpty) {
        return album.tracks!.map((track) => track.asTrack(album)).toList();
      }
      await ref.read(albumTracksProvider(album).future);
      return ref.read(albumTracksProvider(album).notifier).fetchAll();
    }

    return PlaybuttonCard(
        imageUrl: album.images.asUrlString(
          placeholder: ImagePlaceholder.collection,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 10),
        isPlaying: isPlaylistPlaying,
        isLoading: (isPlaylistPlaying && playlist.isFetching == true) ||
            updating.value,
        title: album.name!,
        description:
            "${album.albumType?.formatted} • ${album.artists?.asString() ?? ""}",
        onTap: () {
          ServiceUtils.push(context, "/album/${album.id}", extra: album);
        },
        onPlaybuttonPressed: () async {
          updating.value = true;
          try {
            if (isPlaylistPlaying) {
              return playing ? audioPlayer.pause() : audioPlayer.resume();
            }

            final fetchedTracks = await fetchAllTrack();

            if (fetchedTracks.isEmpty || !context.mounted) return;

            final isRemoteDevice = await showSelectDeviceDialog(context, ref);
            if (isRemoteDevice) {
              final remotePlayback = ref.read(connectProvider.notifier);
              await remotePlayback.load(
                WebSocketLoadEventData(
                  tracks: fetchedTracks,
                  collectionId: album.id!,
                ),
              );
            } else {
              await playlistNotifier.load(fetchedTracks, autoPlay: true);
              playlistNotifier.addCollection(album.id!);
            }
          } finally {
            updating.value = false;
          }
        },
        onAddToQueuePressed: () async {
          if (isPlaylistPlaying) {
            return;
          }

          updating.value = true;
          try {
            final fetchedTracks = await fetchAllTrack();

            if (fetchedTracks.isEmpty) return;
            playlistNotifier.addTracks(fetchedTracks);
            playlistNotifier.addCollection(album.id!);
            if (context.mounted) {
              final snackbar = SnackBar(
                content: Text(
                  context.l10n.added_to_queue(fetchedTracks.length),
                ),
                action: SnackBarAction(
                  label: "Undo",
                  onPressed: () {
                    playlistNotifier
                        .removeTracks(fetchedTracks.map((e) => e.id!));
                  },
                ),
              );

              scaffoldMessenger?.showSnackBar(snackbar);
            }
          } finally {
            updating.value = false;
          }
        });
  }
}
