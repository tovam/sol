import {Assets} from 'assets'
import {observer} from 'mobx-react-lite'
import {Image, Linking, Text, TouchableOpacity, View} from 'react-native'
import packageInfo from '../../../package.json'

export const About = observer(() => {
  return (
    <View className="flex-1 justify-center items-center gap-1">
      <Image
        source={Assets.logoMinimal}
        style={{
          height: 112,
          width: 112,
        }}
      />
      <View className="gap-1.5 items-center">
        <Text className="text-xl font-semibold">Sol</Text>
        <Text className="darker-text text-xxs">{packageInfo.version}</Text>
        <View className="flex-row items-center gap-1.5">
          <Text className="text-sm">by</Text>
          <Image source={Assets.OSP} className="h-5 w-5 rounded-full" />
          <Text className="text-sm">ospfranco</Text>
        </View>
        <View className="flex-row gap-2 mt-4">
          <TouchableOpacity
            className="bg-accent-strong px-3 py-1.5 rounded-md justify-center items-center w-36"
            onPress={() => {
              Linking.openURL('https://x.com/ospfranco')
            }}>
            <Text className="text-sm text-white">Follow Me</Text>
          </TouchableOpacity>
          <TouchableOpacity
            className="bg-accent-strong px-3 py-1.5 rounded-md justify-center items-center w-36"
            onPress={() => {
              Linking.openURL('https://sol.ospfranco.com/')
            }}>
            <Text className="text-sm text-white">Website</Text>
          </TouchableOpacity>
        </View>
      </View>
    </View>
  )
})
